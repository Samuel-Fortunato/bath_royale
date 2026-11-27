-- Private alpha feedback is independent from bathroom/review moderation.
create table app_private.alpha_feedback (
 id uuid primary key,
 retry_hash bytea not null,
 category text not null check(category in ('problem','suggestion','other')),
 description text not null check(description=btrim(description) and app_private.grapheme_length(description) between 5 and 2000 and octet_length(description)<=8000),
 app_version text not null check(length(app_version) between 1 and 64 and app_version ~ '^[A-Za-z0-9.+_-]+$'),
 platform_version text not null check(length(platform_version) between 1 and 96 and platform_version !~ '[[:cntrl:]]'),
 screen_id text not null check(screen_id in ('explore','bathroom','collection','diary','rankings','profile','settings','bathroom_form','review_global','review_details','review_tags','experience','privacy','authentication','diagnostics','moderation','feedback_admin','other')),
 status text not null default 'new' check(status in ('new','reviewed','resolved')),
 submitted_at timestamptz not null default clock_timestamp()
);
create index alpha_feedback_submitted on app_private.alpha_feedback(submitted_at desc);
alter table app_private.alpha_feedback enable row level security;
revoke all on app_private.alpha_feedback from public,anon,authenticated,service_role;

create function public.submit_alpha_feedback(report_id uuid,retry_key uuid,category text,description text,app_version text,platform_version text,screen_id text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare previous app_private.alpha_feedback; fingerprint bytea;
begin
 if report_id is null or retry_key is null or category is null or description is null or app_version is null or platform_version is null or screen_id is null then
  raise exception 'Explicit feedback fields required' using errcode='22023'; end if;
 -- One per-submission retry secret, never a device/account identifier. It is not readable.
 fingerprint:=extensions.digest(retry_key::text,'sha256');
 -- Server-wide bounds cannot be bypassed by replacing client IDs, account or request headers.
 perform pg_advisory_xact_lock(74042012);
 select * into previous from app_private.alpha_feedback where id=report_id;
 if found then
  if previous.retry_hash<>fingerprint or previous.category<>category or previous.description<>description
    or previous.app_version<>app_version or previous.platform_version<>platform_version or previous.screen_id<>screen_id then
   raise exception 'Feedback ID reused' using errcode='22023'; end if;
  return jsonb_build_object('submitted',true);
 end if;
 if (select count(*) from app_private.alpha_feedback)>=5000
   or (select count(*) from app_private.alpha_feedback where submitted_at>clock_timestamp()-interval '1 day')>=100
   or (select count(*) from app_private.alpha_feedback where submitted_at>clock_timestamp()-interval '1 hour')>=30 then
  raise exception 'Feedback limit reached; retry later' using errcode='54000'; end if;
 insert into app_private.alpha_feedback(id,retry_hash,category,description,app_version,platform_version,screen_id)
 values(report_id,fingerprint,category,description,app_version,platform_version,screen_id);
 return jsonb_build_object('submitted',true);
end; $$;
revoke all on function public.submit_alpha_feedback(uuid,uuid,text,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.submit_alpha_feedback(uuid,uuid,text,text,text,text,text) to anon,authenticated;

create function public.alpha_feedback_reports(page integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.is_moderator() then raise exception 'Administrator required' using errcode='42501'; end if;
 if page is null or page<0 or page>99 then raise exception 'Invalid feedback page' using errcode='22023'; end if;
 return jsonb_build_object('reports',coalesce((select jsonb_agg(row_to_json(r)) from (
  select id,category,description,app_version,platform_version,screen_id,status,submitted_at
  from app_private.alpha_feedback order by submitted_at desc,id limit 50 offset page*50
 ) r),'[]'::jsonb));
end; $$;
revoke all on function public.alpha_feedback_reports(integer) from public,anon,authenticated,service_role;
grant execute on function public.alpha_feedback_reports(integer) to authenticated;

create function public.set_alpha_feedback_status(report_id uuid,new_status text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.is_moderator() then raise exception 'Administrator required' using errcode='42501'; end if;
 if new_status is null or new_status not in ('new','reviewed','resolved') then raise exception 'Invalid feedback status' using errcode='22023'; end if;
 update app_private.alpha_feedback set status=new_status where id=report_id;
 if not found then raise exception 'Unknown feedback report' using errcode='22023'; end if;
 return jsonb_build_object('updated',true);
end; $$;
revoke all on function public.set_alpha_feedback_status(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.set_alpha_feedback_status(uuid,text) to authenticated;
