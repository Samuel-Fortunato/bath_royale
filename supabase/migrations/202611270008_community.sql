-- A3 additive community alpha. No historical private records are published.
alter table public.bathrooms add column community boolean not null default false;
alter table public.bathrooms add column hidden boolean not null default false;
alter table public.bathrooms drop constraint bathrooms_check;
alter table public.bathrooms add check(community or ((publication_status='approved') = (approved_by is not null and approved_at is not null)));
alter table public.bathrooms add check(not community or not account_private);
create unique index community_bathroom_name on public.bathrooms(lower(regexp_replace(btrim(name),'[[:space:]]+',' ','g'))) where community;
alter table public.reviews add column public_id uuid not null default gen_random_uuid() unique;
alter table public.reviews add column hidden boolean not null default false;
alter table public.profiles add column public_id uuid not null default gen_random_uuid() unique;
create table app_private.bathroom_links (
 owner_id uuid not null references auth.users(id), private_id uuid not null references public.bathrooms(id),
 shared_id uuid not null references public.bathrooms(id), primary key(owner_id,private_id), check(private_id<>shared_id));
create table app_private.reports (
 id uuid primary key, reporter uuid not null references auth.users(id), kind text not null check(kind in ('bathroom','review')),
 target uuid not null, reason text not null check(app_private.grapheme_length(reason) between 1 and 500),
 resolved boolean not null default false, unique(reporter,kind,target));
alter table app_private.bathroom_links enable row level security;
alter table app_private.reports enable row level security;
revoke all on app_private.bathroom_links,app_private.reports from public,anon,authenticated,service_role;
-- Public readers receive narrow RPC/feed projections, never private profile IDs.
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()));
revoke select on public.profiles from anon;
-- Shared records are readable; contributions and moderation use audited commands.
drop policy bathrooms_read on public.bathrooms;
create policy bathrooms_read on public.bathrooms for select to anon,authenticated using
 (contributor_id=(select auth.uid()) or (not account_private and (select app_private.is_moderator())));
-- Legacy approval cannot promote account-private data; community creation has its own command.
create or replace function public.public_reviews() returns table (
 id uuid,bathroom_id uuid,author_id uuid,username text,rating numeric,paper smallint,hygiene smallint,comfort smallint,aesthetics smallint,tags jsonb,comment text
) language sql stable security definer set search_path='' as $$
 select r.public_id,b.id,p.public_id,p.username,r.rating,r.paper,r.hygiene,r.comfort,r.aesthetics,r.tags,r.comment
 from public.reviews r join public.profiles p on p.id=r.author_id
 left join app_private.bathroom_links l on l.owner_id=r.author_id and l.private_id=r.bathroom_id
 join public.bathrooms b on b.id=coalesce(l.shared_id,r.bathroom_id)
 where r.published and not r.hidden and not b.hidden and not b.account_private and b.publication_status='approved';
$$;
-- Base rows carry Auth IDs and administrative timestamps; catalogue browsing uses only these narrow projections.
create function public.public_catalogue() returns table(id uuid,name text,emoji text,accent smallint,institution text,locality text)
language sql stable security definer set search_path='' as $$
 select id,name,emoji,accent,institution,locality from public.bathrooms where not account_private and not hidden and publication_status='approved';
$$;
revoke all on function public.public_catalogue() from public,anon,authenticated,service_role;
grant execute on function public.public_catalogue() to anon,authenticated;
-- The ordinary immutable-identity guard now allows moderator-only visibility changes.
create or replace function app_private.guard_record() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if (to_jsonb(new) - array['hidden','updated_at','username','name','emoji','accent','institution','locality','publication_status','verification_status','approved_by','approved_at','visited_at','rating','paper','hygiene','comfort','aesthetics','tags','comment','published'])
       is distinct from
       (to_jsonb(old) - array['hidden','updated_at','username','name','emoji','accent','institution','locality','publication_status','verification_status','approved_by','approved_at','visited_at','rating','paper','hygiene','comfort','aesthetics','tags','comment','published']) then
      raise exception 'Immutable identity or association' using errcode = '23514';
    end if;
    new.updated_at := greatest(old.updated_at, clock_timestamp());
  end if;
  return new;
end;
$$;
create or replace function app_private.sync_capture() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  row_data jsonb; subject_id uuid; record_id uuid; kind text;
  gone boolean := tg_op = 'DELETE'; public_payload jsonb; r record;
  catalogue uuid := '00000000-0000-0000-0000-000000000000';
begin
  if gone then row_data := to_jsonb(old); else row_data := to_jsonb(new); end if;
  kind := case tg_table_name when 'bathrooms' then 'bathroom' when 'visits' then 'visit'
    when 'reviews' then 'review' else 'favourite' end;
  subject_id := coalesce(row_data->>'contributor_id',row_data->>'owner_id',row_data->>'author_id')::uuid;
  record_id := case when kind='favourite' then (row_data->>'bathroom_id')::uuid else (row_data->>'id')::uuid end;
  if kind='visit' and not gone then
    select jsonb_build_object('id',b.id,'name',b.name,'emoji',b.emoji,'accent',b.accent) into public_payload
      from public.bathrooms b where b.id=(row_data->>'bathroom_id')::uuid and not b.account_private and b.publication_status='approved';
    if public_payload is not null then perform app_private.sync_emit('private',subject_id,'sharedBathroom',(row_data->>'bathroom_id')::uuid,false,public_payload); end if;
  end if;
  if kind<>'bathroom' or not coalesce((row_data->>'community')::boolean,false) then
  perform app_private.sync_emit('private',subject_id,kind,record_id,gone and kind<>'favourite',
    case when kind='favourite' then jsonb_build_object('value',not gone,'bathroom_id',record_id)
      when gone then '{}'::jsonb else row_data end);
  end if;
  if kind='bathroom' then
    public_payload := jsonb_build_object('id',record_id,'name',row_data->'name',
      'emoji',row_data->'emoji','accent',row_data->'accent',
      'institution',row_data->'institution','locality',row_data->'locality');
    if not gone and row_data->>'publication_status'='approved' and not (row_data->>'hidden')::boolean then
      perform app_private.sync_emit('catalogue',catalogue,kind,record_id,false,public_payload);
    elsif (gone and exists(select 1 from app_private.sync_changes where feed='catalogue' and entity_type=kind and entity_id=record_id))
      or (tg_op='UPDATE' and old.publication_status='approved') then
      perform app_private.sync_emit('catalogue',catalogue,kind,record_id,true,
        case when gone then '{}'::jsonb else '{"_visibility":false}'::jsonb end);
    end if;
    -- Bathroom visibility affects published reviews too, without exposing visits.
    for r in select x.public_id as id from public.reviews x left join app_private.bathroom_links l on l.owner_id=x.author_id and l.private_id=x.bathroom_id where coalesce(l.shared_id,x.bathroom_id)=record_id and x.published loop
      select to_jsonb(p) into public_payload from public.public_reviews() p where p.id=r.id;
      perform app_private.sync_emit('catalogue',catalogue,'review',r.id,public_payload is null,
        coalesce(public_payload,'{"_visibility":false}'::jsonb));
    end loop;
  elsif kind='review' then
    record_id := (row_data->>'public_id')::uuid;
    select to_jsonb(p) into public_payload from public.public_reviews() p where p.id=record_id;
    if public_payload is not null or exists(select 1 from app_private.sync_changes
      where feed='catalogue' and entity_type=kind and entity_id=record_id) then
      perform app_private.sync_emit('catalogue',catalogue,kind,record_id,public_payload is null,
        coalesce(public_payload,case when gone then '{}'::jsonb else '{"_visibility":false}'::jsonb end));
    end if;
  end if;
  return null;
end;
$$;
-- Profile changes refresh public attribution and the owner's private username.
create function app_private.capture_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare r record;
begin
 perform app_private.sync_emit('private',new.id,'profile',new.id,false,jsonb_build_object('username',new.username));
 for r in select * from public.public_reviews() where author_id=new.public_id loop
  perform app_private.sync_emit('catalogue','00000000-0000-0000-0000-000000000000','review',r.id,false,to_jsonb(r));
 end loop;
 return null;
end; $$;
drop trigger sync_lock_profiles on public.profiles;
drop trigger sync_profile_projection on public.profiles;
create trigger sync_lock_profiles before insert or update on public.profiles for each statement execute function app_private.sync_lock();
create trigger capture_profile after insert or update on public.profiles for each row execute function app_private.capture_profile();
alter function public.sync_submit(jsonb) rename to private_sync_submit;
alter function public.private_sync_submit(jsonb) set schema app_private;
revoke all on function app_private.private_sync_submit(jsonb) from public,anon,authenticated,service_role;
-- Extend the same receipt/CAS protocol; arbitrary base-table writes cannot bypass publication rules.
create or replace function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); op uuid; kind text; target uuid; action text; p jsonb;
 receipt app_private.sync_receipts; state app_private.sync_records; expected bigint; outcome jsonb; rev bigint;
 dep record; entity jsonb; r public.reviews; b public.bathrooms; link uuid; visible boolean;
begin
 action:=command->>'type';
 if action not in ('contributeBathroom','linkBathroom','setUsername','publishReview','withdrawReview','reportContent') then
  return app_private.private_sync_submit(command);
 end if;
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform app_private.sync_keys(command,array['operationId','entityType','entityId','type','payload','baseRevision','dependencies']);
 op:=(command->>'operationId')::uuid; target:=(command->>'entityId')::uuid; kind:=command->>'entityType'; p:=command->'payload';
 if op is null or target is null or kind is null or jsonb_typeof(command->'dependencies') is distinct from 'object' then
  raise exception 'Invalid command' using errcode='22023'; end if;
 perform app_private.sync_revision();
 select * into receipt from app_private.sync_receipts where subject=actor and operation_id=op;
 if found then
  if receipt.request<>command then raise exception 'Operation ID reused' using errcode='22023'; end if;
  return receipt.outcome;
 end if;
 expected:=(command->>'baseRevision')::bigint;
 for dep in select * from jsonb_each(command->'dependencies') loop
  select * into receipt from app_private.sync_receipts where subject=actor and operation_id=dep.key::uuid;
  if not found or receipt.outcome->>'status'<>'acknowledged' or receipt.outcome->'revision' is distinct from dep.value then
   raise exception 'Invalid predecessor' using errcode='22023'; end if;
  for entity in select value from jsonb_array_elements(receipt.outcome->'entities') loop
   if entity->>'entityType'=kind and entity->>'entityId'=target::text then expected:=greatest(expected,(entity->>'revision')::bigint); end if;
  end loop;
 end loop;
 select * into state from app_private.sync_records where subject=actor and entity_type=kind and entity_id=target;
 if found and expected is distinct from state.revision then
  outcome:=jsonb_build_object('subject',actor,'status','conflict','conflict',jsonb_build_object('entityType',kind,'entityId',target,'revision',state.revision,'deleted',state.deleted,'payload',state.payload));
  insert into app_private.sync_receipts values(actor,op,command,outcome); return outcome;
 end if;
 if not found and expected is not null then raise exception 'Unknown base' using errcode='22023'; end if;
 if action='contributeBathroom' and kind='contribution' then
  perform app_private.sync_keys(p,array['name','emoji','accent']);
  if p->>'name' ~ '[[:cntrl:]]' then raise exception 'Invalid name' using errcode='22023'; end if;
  if exists(select 1 from public.bathrooms where not account_private and publication_status='approved'
    and lower(regexp_replace(btrim(name),'[[:space:]]+',' ','g'))=lower(regexp_replace(btrim(p->>'name'),'[[:space:]]+',' ','g'))) then
    raise exception 'Duplicate catalogue name; choose the existing bathroom' using errcode='23505'; end if;
  insert into public.bathrooms(id,name,emoji,accent,contributor_id,community,publication_status)
   values(target,p->>'name',p->>'emoji',(p->>'accent')::smallint,actor,true,'approved');
  entity:=jsonb_build_object('shared_id',target);
 elsif action='setUsername' and kind='profile' and target=actor then
  perform app_private.sync_keys(p,array['username']);
  insert into public.profiles(id,username) values(actor,p->>'username') on conflict(id) do update set username=excluded.username;
  entity:=p;
 elsif action='linkBathroom' and kind='link' then
  perform app_private.sync_keys(p,array['shared_id']); link:=(p->>'shared_id')::uuid;
  if not exists(select 1 from public.bathrooms where id=target and contributor_id=actor and account_private)
    or not exists(select 1 from public.bathrooms where id=link and not account_private and publication_status='approved' and not hidden) then
   raise exception 'Unavailable association' using errcode='42501'; end if;
  -- An established association is immutable: relinking published history requires a later product decision.
  insert into app_private.bathroom_links values(actor,target,link) on conflict(owner_id,private_id) do nothing;
  if not exists(select 1 from app_private.bathroom_links where owner_id=actor and private_id=target and shared_id=link) then
   raise exception 'Association already exists' using errcode='22023'; end if;
  perform app_private.sync_emit('private',actor,'sharedBathroom',link,false,
    (select jsonb_build_object('id',id,'name',name,'emoji',emoji,'accent',accent) from public.bathrooms where id=link));
  entity:=p;
 elsif action in ('publishReview','withdrawReview') and kind='publication' then
  perform app_private.sync_keys(p,array['review_id','published']);
  select * into r from public.reviews where id=(p->>'review_id')::uuid and author_id=actor;
  if not found or r.id<>target then raise exception 'Owned review required' using errcode='42501'; end if;
  visible:=action='publishReview';
  if p->'published' is distinct from to_jsonb(visible) then raise exception 'Publication state mismatch' using errcode='22023'; end if;
  select shared_id into link from app_private.bathroom_links where owner_id=actor and private_id=r.bathroom_id;
  if visible and (r.hidden or not exists(select 1 from public.profiles where id=actor)
   or not exists(select 1 from public.bathrooms where id=coalesce(link,r.bathroom_id) and not account_private and publication_status='approved' and not hidden)) then
   raise exception 'Public username and available shared bathroom required' using errcode='42501'; end if;
  update public.reviews set published=visible where id=r.id;
  entity:=jsonb_build_object('review_id',r.id,'public_id',r.public_id,'published',visible,'hidden',r.hidden);
 elsif action='reportContent' and kind='report' then
  perform app_private.sync_keys(p,array['kind','target','reason']);
  if not ((p->>'kind'='bathroom' and exists(select 1 from public.bathrooms where id=(p->>'target')::uuid and not account_private and publication_status='approved' and not hidden))
    or (p->>'kind'='review' and exists(select 1 from public.public_reviews() where id=(p->>'target')::uuid))) then
   raise exception 'Public content required' using errcode='42501'; end if;
  insert into app_private.reports(id,reporter,kind,target,reason) values(target,actor,p->>'kind',(p->>'target')::uuid,btrim(p->>'reason'))
   on conflict on constraint reports_reporter_kind_target_key do nothing;
  entity:=jsonb_build_object('received',true);
 else raise exception 'Invalid community command' using errcode='22023'; end if;
 perform app_private.sync_emit('private',actor,kind,target,false,entity);
 rev:=app_private.sync_revision();
 outcome:=jsonb_build_object('subject',actor,'status','acknowledged','revision',rev,'entities',
  (select jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'revision',revision,'deleted',deleted)) from app_private.sync_records where subject=actor and revision=rev));
 insert into app_private.sync_receipts values(actor,op,command,outcome); return outcome;
end; $$;
create function app_private.review_publishable(bathroom uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.bathrooms b
 left join app_private.bathroom_links l on l.owner_id=auth.uid() and l.private_id=bathroom
 where b.id=coalesce(l.shared_id,bathroom) and not b.account_private and b.publication_status='approved' and not b.hidden);
$$;
revoke all on function app_private.review_publishable(uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.review_publishable(uuid) to authenticated;
drop policy reviews_own on public.reviews;
create policy reviews_own on public.reviews to authenticated using(author_id=(select auth.uid()))
 with check(author_id=(select auth.uid()) and (not published or app_private.review_publishable(bathroom_id)));
drop policy visits_insert on public.visits;
create policy visits_insert on public.visits for insert to authenticated with check(owner_id=(select auth.uid()) and
 (app_private.review_publishable(bathroom_id) or exists(select 1 from public.bathrooms b where b.id=bathroom_id and b.contributor_id=(select auth.uid()) and b.account_private)));
drop policy favourites_own on public.favourites;
create policy favourites_own on public.favourites to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()) and
 (app_private.review_publishable(bathroom_id) or exists(select 1 from public.bathrooms b where b.id=bathroom_id and b.contributor_id=(select auth.uid()) and b.account_private)));
-- Publication can only change through explicit owner commands, never generic REST.
revoke insert(published),update(published) on public.reviews from authenticated;
-- Existing API clients retain private editing, but a forged published insert is rejected by column grants.
create function public.moderation_reports() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.is_moderator() then raise exception 'Moderator required' using errcode='42501'; end if;
 return jsonb_build_object('reports',coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'target',target,'reason',reason,'resolved',resolved)) from app_private.reports),'[]'::jsonb));
end; $$;
create function public.moderate_content(content_kind text, content_id uuid, hide boolean, report_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.is_moderator() then raise exception 'Moderator required' using errcode='42501'; end if;
 if content_kind='review' then update public.reviews set hidden=hide where public_id=content_id;
 elsif content_kind='bathroom' then update public.bathrooms set hidden=hide where id=content_id and not account_private;
 else raise exception 'Invalid kind' using errcode='22023'; end if;
 if not found then raise exception 'Unavailable content' using errcode='22023'; end if;
 update app_private.reports set resolved=true where id=report_id and kind=content_kind and target=content_id;
 return jsonb_build_object('updated',true);
end; $$;
revoke all on function public.moderation_reports(),public.moderate_content(text,uuid,boolean,uuid) from public,anon,authenticated,service_role;
grant execute on function public.moderation_reports(),public.moderate_content(text,uuid,boolean,uuid) to authenticated;
revoke all on function app_private.capture_profile() from public,anon,authenticated,service_role;
create or replace function public.sync_pull(feed text, checkpoint uuid default null, page_size integer default 20) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  subject_id uuid; cursor_row app_private.sync_cursors; last_position bigint:=0;
  result jsonb; next_cursor uuid; reset boolean:=false;
begin
  if feed='private' then
    subject_id:=auth.uid();
    if subject_id is null then
      raise exception 'Authentication required' using errcode='42501'; end if;
  elsif feed='catalogue' then subject_id:='00000000-0000-0000-0000-000000000000';
  else raise exception 'Unknown feed' using errcode='22023'; end if;
  if page_size is null or page_size not between 1 and 100 then raise exception 'Invalid page size' using errcode='22023'; end if;
  if checkpoint is not null then
    select * into cursor_row from app_private.sync_cursors where id=checkpoint and sync_cursors.feed=sync_pull.feed and subject=subject_id;
    if not found then raise exception 'Invalid scoped checkpoint' using errcode='22023'; end if;
    if cursor_row.expires_at <= now() then reset:=true; else last_position:=cursor_row.position; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'revision',revision,
    'deleted',case when sync_pull.feed='catalogue' then current_payload is null else deleted end,'payload',case when sync_pull.feed='catalogue' then coalesce(current_payload,'{"_visibility":false}'::jsonb) else payload end) order by position),'[]'::jsonb),coalesce(max(position),last_position)
  into result,last_position from (
    select c.*, case when c.entity_type='bathroom' then
      (select jsonb_build_object('id',b.id,'name',b.name,'emoji',b.emoji,'accent',b.accent) from public.bathrooms b where b.id=c.entity_id and not b.account_private and not b.hidden and b.publication_status='approved')
      when c.entity_type='review' then (select to_jsonb(r) from public.public_reviews() r where r.id=c.entity_id) end as current_payload
    from app_private.sync_changes c where c.feed=sync_pull.feed and subject=subject_id and position>last_position
    order by position limit page_size
  ) page;
  insert into app_private.sync_cursors(feed,subject,position) values(feed,subject_id,last_position) returning id into next_cursor;
  return jsonb_build_object('subject',case when feed='private' then subject_id else null end,
    'changes',result,'checkpoint',next_cursor,'reset',reset);
end;
$$;


-- Rebuild only the disposable public projection, preserving every domain/private row.
-- Old public review IDs were private IDs; they cannot remain in readable history.
delete from app_private.sync_changes where feed='catalogue' and entity_type='review';
update app_private.sync_cursors set expires_at=now() where feed='catalogue';
do $$ declare r record; begin
 for r in select * from public.public_reviews() loop
  perform app_private.sync_emit('catalogue','00000000-0000-0000-0000-000000000000','review',r.id,false,to_jsonb(r));
 end loop;
 for r in select * from public.profiles loop
  perform app_private.sync_emit('private',r.id,'profile',r.id,false,jsonb_build_object('username',r.username));
 end loop;
end; $$;

revoke all on function public.sync_submit(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sync_submit(jsonb) to authenticated;
