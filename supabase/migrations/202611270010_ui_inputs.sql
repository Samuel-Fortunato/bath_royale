-- A4 additive identities and versioned rating inputs. Never rewrite domain scores/colours.
alter table public.bathrooms add column accent_rgb integer check(accent_rgb between 0 and 16777215);
alter table public.bathrooms drop constraint bathrooms_emoji_check;
alter table public.bathrooms add constraint bathrooms_emoji_check check(app_private.valid_tag_emoji(emoji));

-- Extend the existing receipt/CAS implementations in place. Legacy commands retain exact replay.
do $migration$
declare definition text;
begin
 select pg_get_functiondef('app_private.private_sync_submit(jsonb)'::regprocedure) into definition;
 if position('''creator'',''emoji'',''accent'',''provenance''' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'''creator'',''emoji'',''accent'',''provenance''','''creator'',''emoji'',''accent'',''provenance'',''accent_rgb''');
 if position('id,name,emoji,accent,contributor_id,account_private' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'id,name,emoji,accent,contributor_id,account_private','id,name,emoji,accent,contributor_id,account_private,accent_rgb');
 if position('(p->>''accent'')::smallint,actor,true)' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'(p->>''accent'')::smallint,actor,true)','(p->>''accent'')::smallint,actor,true,(p->>''accent_rgb'')::integer)');
 if position('accent=(p->>''accent'')::smallint' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'accent=(p->>''accent'')::smallint','accent=(p->>''accent'')::smallint,accent_rgb=(p->>''accent_rgb'')::integer');
 execute definition;
 select pg_get_functiondef('app_private.a3_sync_submit(jsonb)'::regprocedure) into definition;
 if position('array[''name'',''emoji'',''accent'']' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'array[''name'',''emoji'',''accent'']','array[''name'',''emoji'',''accent'',''accent_rgb'']');
 if position('id,name,emoji,accent,contributor_id,community,publication_status)' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'id,name,emoji,accent,contributor_id,community,publication_status)','id,name,emoji,accent,contributor_id,community,publication_status,accent_rgb)');
 if position('(p->>''accent'')::smallint,actor,true,''approved'')' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'(p->>''accent'')::smallint,actor,true,''approved'')','(p->>''accent'')::smallint,actor,true,''approved'',(p->>''accent_rgb'')::integer)');
 execute definition;
 select pg_get_functiondef('app_private.sync_capture()'::regprocedure) into definition;
 if position('''accent'',b.accent' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'''accent'',b.accent','''accent'',b.accent,''accent_rgb'',b.accent_rgb');
 if position('''accent'',row_data->''accent''' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'''accent'',row_data->''accent''','''accent'',row_data->''accent'',''accent_rgb'',row_data->''accent_rgb''');
 execute definition;
 select pg_get_functiondef('public.sync_pull(text,uuid,integer)'::regprocedure) into definition;
 if position('item:=jsonb_set(item,''{payload}'',(item->''payload'')||jsonb_build_object(''classification'',kind));' in definition)=0 then raise exception 'A4 migration source mismatch'; end if;
 definition:=replace(definition,'item:=jsonb_set(item,''{payload}'',(item->''payload'')||jsonb_build_object(''classification'',kind));','item:=jsonb_set(item,''{payload}'',(item->''payload'')||jsonb_build_object(''classification'',kind,''accent_rgb'',(select accent_rgb from public.bathrooms where id=(item->>''entityId'')::uuid)));');
 execute definition;
end; $migration$;
drop function public.public_catalogue();
create function public.public_catalogue() returns table(id uuid,name text,emoji text,accent smallint,institution text,locality text,classification text,accent_rgb integer)
language sql stable security definer set search_path='' as $$
 select id,name,emoji,accent,institution,locality,case when origin='curated' then 'official' else 'community' end,accent_rgb
 from public.bathrooms where not account_private and not hidden and publication_status='approved';
$$;
revoke all on function public.public_catalogue() from public,anon,authenticated,service_role;
grant execute on function public.public_catalogue() to anon,authenticated;

alter function public.sync_submit(jsonb) rename to a31_sync_submit;
alter function public.a31_sync_submit(jsonb) set schema app_private;
revoke all on function app_private.a31_sync_submit(jsonb) from public,anon,authenticated,service_role;
create function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt app_private.sync_receipts; op uuid; action text:=command->>'type';
 translated jsonb; outcome jsonb; score numeric; old_score numeric;
begin
 if action not in ('createReviewV2','createVisitReviewV2','createCommunityReviewV2','createCommunityVisitReviewV2','updateReviewV2') then
   return app_private.a31_sync_submit(command);
 end if;
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 perform app_private.sync_keys(command,array['operationId','entityType','entityId','type','payload','baseRevision','dependencies']);
 op:=(command->>'operationId')::uuid;
 perform app_private.sync_revision();
 select * into receipt from app_private.sync_receipts where subject=actor and operation_id=op;
 if found then
  if receipt.request<>command then raise exception 'Operation ID reused' using errcode='22023'; end if;
  return receipt.outcome;
 end if;
 score:=(command->'payload'->'review'->>'rating')::numeric;
 if action='updateReviewV2' then
  select rating into old_score from public.reviews where id=(command->>'entityId')::uuid and author_id=actor;
 end if;
 if score is null or (score is distinct from old_score and (score<1 or score>5 or score<>trunc(score))) then
  raise exception 'Choose an integer rating from 1 to 5' using errcode='22023';
 end if;
 translated:=jsonb_set(command,'{type}',to_jsonb(left(action,length(action)-2)));
 outcome:=app_private.a31_sync_submit(translated);
 update app_private.sync_receipts set request=command where subject=actor and operation_id=op;
 return outcome;
end; $$;
revoke all on function public.sync_submit(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.sync_submit(jsonb) to authenticated;
-- Existing fractional/zero rows, original accent indices and pending payloads are unchanged.
-- Public pull enriches existing cached bathroom projections on the next full refresh.
update app_private.sync_cursors set expires_at=now() where feed='catalogue';
