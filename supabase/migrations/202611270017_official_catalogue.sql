-- Operator import baseline, kept private and included in logical backups.
-- No import function or client API is installed.
create table app_private.official_catalogue (
  key text primary key check(key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  bathroom_id uuid not null unique references public.bathrooms(id),
  applied_content jsonb not null check(jsonb_typeof(applied_content)='object')
);
alter table app_private.official_catalogue enable row level security;
revoke all on app_private.official_catalogue from public,anon,authenticated,service_role;

-- RGB is mutable appearance, like the legacy accent. Identity/associations stay
-- immutable; retain guard timestamps and all domain/publication capture triggers.
do $migration$
declare definition text;
begin
 select pg_get_functiondef('app_private.guard_record()'::regprocedure) into definition;
 if position('''name'',''emoji'',''accent''' in definition)=0 then
  raise exception 'Appearance guard source mismatch';
 end if;
 definition:=replace(definition,'''name'',''emoji'',''accent''','''name'',''emoji'',''accent'',''accent_rgb''');
 execute definition;
end; $migration$;
