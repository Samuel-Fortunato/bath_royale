-- Deployment must explicitly enable these free-plan Auth hooks/settings.
create table app_private.alpha_signup_buckets(day date primary key, attempts integer not null);
create table app_private.alpha_recovery(user_id uuid primary key references auth.users(id) on delete cascade, digest bytea not null, created_at timestamptz not null default now());
alter table app_private.alpha_signup_buckets enable row level security;
alter table app_private.alpha_recovery enable row level security;
revoke all on app_private.alpha_signup_buckets,app_private.alpha_recovery from public,anon,authenticated,service_role;
create function public.alpha_no_email(event jsonb) returns jsonb language sql set search_path='' as $$
 select '{"error":{"http_code":403,"message":"Email authentication is unavailable in this alpha. Use your saved recovery code."}}'::jsonb;
$$;
create function public.alpha_signup_limit(event jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare accepted integer;
begin
 delete from app_private.alpha_signup_buckets where day<current_date-30;
 insert into app_private.alpha_signup_buckets values(current_date,1)
 on conflict(day) do update set attempts=alpha_signup_buckets.attempts+1 where alpha_signup_buckets.attempts<100 returning attempts into accepted;
 if accepted is null or (select count(*) from auth.users)>=3000 then
 return '{"error":{"http_code":429,"message":"Registration limit reached. Try again later."}}'::jsonb; end if;
 return '{}'::jsonb;
end; $$;
revoke all on function public.alpha_no_email(jsonb),public.alpha_signup_limit(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.alpha_no_email(jsonb),public.alpha_signup_limit(jsonb) to supabase_auth_admin;
-- One replacement code, revealed once, following a password sign-in in the last five minutes.
create function public.create_alpha_recovery_code() returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); code text;
begin
 if actor is null or not exists(select 1 from auth.sessions s where s.id=(auth.jwt()->>'session_id')::uuid and s.user_id=actor and s.created_at>now()-interval '5 minutes')
 or not exists(select 1 from jsonb_array_elements(auth.jwt()->'amr') a where a->>'method'='password') then
 raise exception 'Recent password sign-in required' using errcode='42501'; end if;
 code:=encode(extensions.gen_random_bytes(32),'hex');
 insert into app_private.alpha_recovery(user_id,digest) values(actor,extensions.digest(code,'sha256')) on conflict(user_id) do update set digest=excluded.digest,created_at=now();
 return actor::text||':'||code;
end; $$;
revoke all on function public.create_alpha_recovery_code() from public,anon,authenticated,service_role;
grant execute on function public.create_alpha_recovery_code() to authenticated;
