-- Operator-only proof consumption and erasure. No anonymous/admin-UI RPC grants.
create function app_private.consume_alpha_recovery(proof text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid; secret text; result uuid;
begin
 if proof !~ '^[0-9a-f-]{36}:[0-9a-f]{64}$' then raise exception 'Invalid recovery proof'; end if;
 actor:=split_part(proof,':',1)::uuid; secret:=split_part(proof,':',2);
 delete from app_private.alpha_recovery where user_id=actor and digest=extensions.digest(secret,'sha256') returning user_id into result;
 if result is null then raise exception 'Invalid recovery proof'; end if;
 return result;
end; $$;
alter table public.bathrooms alter column contributor_id drop not null;
create function app_private.erase_alpha_domain(actor uuid) returns void language plpgsql security definer set search_path='' as $$
declare public_ids uuid[];
begin
 if actor is null then raise exception 'Explicit account required'; end if;
 -- Legacy rows need individual review, never cascade another account's history.
 if exists(select 1 from public.bathrooms where (contributor_id=actor or approved_by=actor) and not community and not account_private)
 or exists(select 1 from public.visits v join public.bathrooms b on b.id=v.bathroom_id where b.account_private and b.contributor_id=actor and v.owner_id<>actor)
 then raise exception 'Review legacy references before erasure'; end if;
 perform app_private.sync_revision();
 select array_agg(public_id) into public_ids from public.reviews where author_id=actor;
 delete from public.reviews where author_id=actor;
 delete from public.visits where owner_id=actor;
 delete from public.favourites where owner_id=actor;
 delete from app_private.bathroom_links where owner_id=actor;
 delete from public.bathrooms where account_private and contributor_id=actor;
 update public.bathrooms set contributor_id=null where community and contributor_id=actor;
 update public.bathrooms set approved_by=null where community and approved_by=actor;
 delete from app_private.reports where reporter=actor;
 delete from app_private.bathroom_creators where user_id=actor;
 delete from app_private.moderators where user_id=actor;
 delete from public.profiles where id=actor;
 delete from app_private.alpha_recovery where user_id=actor;
 delete from app_private.sync_receipts where subject=actor;
 delete from app_private.sync_cursors where subject=actor;
 delete from app_private.sync_records where subject=actor;
 delete from app_private.sync_changes where subject=actor;
 -- Keep public removal markers, erase old public review bodies.
 delete from app_private.sync_changes where feed='catalogue' and entity_type='review' and entity_id=any(public_ids) and not deleted;
end; $$;
revoke all on function app_private.consume_alpha_recovery(text),app_private.erase_alpha_domain(uuid) from public,anon,authenticated,service_role;
