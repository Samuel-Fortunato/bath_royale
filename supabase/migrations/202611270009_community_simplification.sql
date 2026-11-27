-- A3.1: shared submissions are anonymous; historical private commands stay private.
create table app_private.bathroom_creators(user_id uuid primary key references auth.users(id));
alter table app_private.bathroom_creators enable row level security;
revoke all on app_private.bathroom_creators from public,anon,authenticated,service_role;

create function app_private.account_capabilities(actor uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('moderator',exists(select 1 from app_private.moderators where user_id=actor),
 'create_bathroom',exists(select 1 from app_private.bathroom_creators where user_id=actor));
$$;
revoke all on function app_private.account_capabilities(uuid) from public,anon,authenticated,service_role;
create function public.grant_bathroom_creation(account_email text, allowed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if auth.uid() is null or not app_private.is_moderator() then raise exception 'Administrator required' using errcode='42501'; end if;
 if allowed is null then raise exception 'Explicit entitlement state required' using errcode='22023'; end if;
 perform app_private.sync_revision();
 select id into target from auth.users where lower(email)=lower(btrim(account_email));
 if target is null then raise exception 'Account not found' using errcode='22023'; end if;
 if allowed then insert into app_private.bathroom_creators values(target) on conflict do nothing;
 else delete from app_private.bathroom_creators where user_id=target; end if;
 perform app_private.sync_emit('private',target,'capabilities',target,false,app_private.account_capabilities(target));
 return jsonb_build_object('updated',true);
end; $$;
revoke all on function public.grant_bathroom_creation(text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.grant_bathroom_creation(text,boolean) to authenticated;

-- No stable author identifier or profile join in public responses.
drop function public.public_reviews();
create function public.public_reviews() returns table(id uuid,bathroom_id uuid,rating numeric,paper smallint,hygiene smallint,comfort smallint,aesthetics smallint,tags jsonb,comment text)
language sql stable security definer set search_path='' as $$
 select r.public_id,b.id,r.rating,r.paper,r.hygiene,r.comfort,r.aesthetics,r.tags,r.comment
 from public.reviews r left join app_private.bathroom_links l on l.owner_id=r.author_id and l.private_id=r.bathroom_id
 join public.bathrooms b on b.id=coalesce(l.shared_id,r.bathroom_id)
 where r.published and not r.hidden and not b.hidden and not b.account_private and b.publication_status='approved';
$$;
revoke all on function public.public_reviews() from public,anon,authenticated,service_role;
grant execute on function public.public_reviews() to anon,authenticated;
create or replace function app_private.capture_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform app_private.sync_emit('private',new.id,'profile',new.id,false,jsonb_build_object('username',new.username));
 return null;
end; $$;
drop function public.public_catalogue();
create function public.public_catalogue() returns table(id uuid,name text,emoji text,accent smallint,institution text,locality text,classification text)
language sql stable security definer set search_path='' as $$
 select id,name,emoji,accent,institution,locality,case when origin='curated' then 'official' else 'community' end
 from public.bathrooms where not account_private and not hidden and publication_status='approved';
$$;
revoke all on function public.public_catalogue() from public,anon,authenticated,service_role;
grant execute on function public.public_catalogue() to anon,authenticated;

alter function public.sync_submit(jsonb) rename to a3_sync_submit;
alter function public.a3_sync_submit(jsonb) set schema app_private;
revoke all on function app_private.a3_sync_submit(jsonb) from public,anon,authenticated,service_role;
create function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt app_private.sync_receipts; action text:=command->>'type';
 op uuid; target uuid; translated jsonb; result_outcome jsonb; source jsonb; bathroom uuid; rev bigint;
begin
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform app_private.sync_keys(command,array['operationId','entityType','entityId','type','payload','baseRevision','dependencies']);
 op:=(command->>'operationId')::uuid; target:=(command->>'entityId')::uuid;
 perform app_private.sync_revision();
 select * into receipt from app_private.sync_receipts where subject=actor and operation_id=op;
 if found then
  if receipt.request<>command then raise exception 'Operation ID reused' using errcode='22023'; end if;
  return receipt.outcome;
 end if;
 if action in ('linkBathroom','publishReview','setUsername') then
  raise exception 'Historical publication and association are no longer supported' using errcode='42501';
 end if;
 if action='contributeBathroom' and not exists(select 1 from app_private.bathroom_creators where user_id=actor) then
  raise exception 'Bathroom creation entitlement required' using errcode='42501';
 end if;
 if action in ('createCommunityReview','createCommunityVisitReview') then
  source:=command->'payload'->'review'; bathroom:=(source->>'bathroom')::uuid;
  if not exists(select 1 from public.bathrooms where id=bathroom and not account_private and not hidden and publication_status='approved') then
   raise exception 'Available shared bathroom required' using errcode='42501'; end if;
  translated:=jsonb_set(command,'{type}',to_jsonb(case when action='createCommunityReview' then 'createReview' else 'createVisitReview' end));
  result_outcome:=app_private.a3_sync_submit(translated);
  if result_outcome->>'status'='acknowledged' then
   update public.reviews set published=true where id=target and author_id=actor and bathroom_id=bathroom;
   if not found then raise exception 'Owned review required' using errcode='42501'; end if;
   rev:=app_private.sync_revision();
   result_outcome:=jsonb_build_object('subject',actor,'status','acknowledged','revision',rev,'entities',
    (select jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'revision',revision,'deleted',deleted)) from app_private.sync_records where subject=actor and revision=rev));
  end if;
  update app_private.sync_receipts set request=command,outcome=result_outcome where subject=actor and operation_id=op;
  return result_outcome;
 end if;
 -- Compatibility commands preserve old private rows and pending A2/A3 writes.
 -- They cannot promote a bathroom or make historical private reviews public.
 return app_private.a3_sync_submit(command);
end; $$;
revoke all on function public.sync_submit(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sync_submit(jsonb) to authenticated;
-- Shared creation and new review submission go through the authorized protocol.
revoke insert on public.bathrooms,public.reviews from authenticated;
revoke insert(name,emoji,accent,institution,locality) on public.bathrooms from authenticated;
revoke insert(visit_id,bathroom_id,rating,paper,hygiene,comfort,aesthetics,tags,comment) on public.reviews from authenticated;

alter function public.sync_pull(text,uuid,integer) rename to a3_sync_pull;
alter function public.a3_sync_pull(text,uuid,integer) set schema app_private;
-- PL/pgSQL parameter qualification uses the function's current block label.
do $migration$ declare definition text; begin
 select pg_get_functiondef('app_private.a3_sync_pull(text,uuid,integer)'::regprocedure) into definition;
 execute replace(definition,'sync_pull.feed','a3_sync_pull.feed');
end $migration$;
revoke all on function app_private.a3_sync_pull(text,uuid,integer) from public,anon,authenticated,service_role;
create function public.sync_pull(feed text,checkpoint uuid default null,page_size integer default 20) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); caps jsonb; result jsonb; item jsonb; changes jsonb:='[]'; kind text;
begin
 if feed='private' then
  if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
  caps:=app_private.account_capabilities(actor);
  if not exists(select 1 from app_private.sync_records where subject=actor and entity_type='capabilities' and entity_id=actor and payload=caps) then
   perform app_private.sync_emit('private',actor,'capabilities',actor,false,caps);
  end if;
 end if;
 result:=app_private.a3_sync_pull(feed,checkpoint,page_size);
 if feed='catalogue' then
  for item in select value from jsonb_array_elements(result->'changes') loop
   if item->>'entityType'='bathroom' and item->>'deleted'='false' then
    select case when origin='curated' then 'official' else 'community' end into kind from public.bathrooms where id=(item->>'entityId')::uuid;
    item:=jsonb_set(item,'{payload}',(item->'payload')||jsonb_build_object('classification',kind));
   end if;
   changes:=changes||jsonb_build_array(item);
  end loop;
  result:=jsonb_set(result,'{changes}',changes);
 end if;
 return result;
end; $$;
revoke all on function public.sync_pull(text,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.sync_pull(text,uuid,integer) to anon,authenticated;
-- Remove only obsolete public attribution cache fields, never domain/history rows.
update app_private.sync_changes set payload=payload-'author_id'-'username' where feed='catalogue' and entity_type='review';
update app_private.sync_cursors set expires_at=now() where feed='catalogue';
