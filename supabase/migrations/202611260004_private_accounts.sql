-- A2: Auth identity owns private data; a public profile is optional.
alter table public.bathrooms drop constraint bathrooms_contributor_id_fkey;
alter table public.bathrooms add foreign key(contributor_id) references auth.users(id);
alter table public.visits drop constraint visits_owner_id_fkey;
alter table public.visits add foreign key(owner_id) references auth.users(id);
alter table public.reviews drop constraint reviews_author_id_fkey;
alter table public.reviews add foreign key(author_id) references auth.users(id);
alter table public.favourites drop constraint favourites_owner_id_fkey;
alter table public.favourites add foreign key(owner_id) references auth.users(id);
-- Private account bathrooms are never proposals for moderator publication.
alter table public.bathrooms add column account_private boolean not null default false;
alter table public.bathrooms add check(not account_private or
 (publication_status='pending' and verification_status='unverified' and approved_by is null and approved_at is null));
drop policy bathrooms_read on public.bathrooms;
create policy bathrooms_read on public.bathrooms for select to anon,authenticated using
(contributor_id=(select auth.uid()) or (not account_private and
 (publication_status='approved' or (select app_private.is_moderator()))));
-- A3 publication remains separate; no profile is manufactured or published.
drop policy visits_insert on public.visits;
create policy visits_insert on public.visits for insert to authenticated with check
(owner_id=(select auth.uid()) and exists(select 1 from public.bathrooms b
 where b.id=bathroom_id and (b.publication_status='approved' or (b.contributor_id=(select auth.uid()) and b.account_private))));
drop policy favourites_own on public.favourites;
create policy favourites_own on public.favourites to authenticated using(owner_id=(select auth.uid())) with check
(owner_id=(select auth.uid()) and exists(select 1 from public.bathrooms b
 where b.id=bathroom_id and (b.publication_status='approved' or (b.contributor_id=(select auth.uid()) and b.account_private))));
create function app_private.valid_tag_emoji(value text) returns boolean
language plpgsql immutable strict set search_path = '' as $$
declare first integer:=ascii(value); last integer:=ascii(right(value,1));
begin
 if app_private.grapheme_length(value)<>1 then return false; end if;
 if first in (8205,65039) or first between 127995 and 127999 then return false; end if;
 if first between 127462 and 127487 then
   return char_length(value)=2 and last between 127462 and 127487; end if;
 if first in (35,42) or first between 48 and 57 then return last=8419; end if;
 return first between 126976 and 129791 or first between 9728 and 10175
  or first in (169,174,8252,8265,8482,8505,8986,8987,9000,9167,
  9193,9194,9195,9196,9197,9198,9199,9200,9201,9202,9203,9208,9209,9210,
  9410,11088,11093,12336,12349,12951,12953);
end;
$$;
create or replace function app_private.valid_tags(tags jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  item jsonb; label text; canonical text; seen text[] := '{}';
begin
  if jsonb_typeof(tags) <> 'array' then return false; end if;
  if jsonb_array_length(tags) > 10 then return false; end if;
  for item in select value from jsonb_array_elements(tags) loop
    if jsonb_typeof(item) <> 'object' or not (item ?& array['emoji','label','key','version'])
       or (select count(*) from jsonb_object_keys(item)) <> 4
       or jsonb_typeof(item->'label') <> 'string' or jsonb_typeof(item->'emoji') <> 'string'
       or jsonb_typeof(item->'key') <> 'string' or item->'version' <> '1'::jsonb then return false; end if;
    label := item->>'label';
    if app_private.grapheme_length(label) not between 1 and 30 or label <> btrim(label)
       or label ~ '[\n\r,]' or label ~ '[[:space:]]{2}' then return false; end if;
    canonical := lower(label);
    if canonical = 'grafiti' then canonical := 'graffiti'; end if;
    if item->>'key' <> canonical or canonical = any(seen) then return false; end if;
    if not app_private.valid_tag_emoji(item->>'emoji') then return false; end if;
    seen := array_append(seen, canonical);
  end loop;
  return true;
end;
$$;

alter table public.bathrooms drop constraint bathrooms_name_check;
alter table public.bathrooms add check(name=btrim(name) and app_private.grapheme_length(name) between 1 and 100);
alter table public.reviews drop constraint reviews_comment_check;
alter table public.reviews add check(comment=btrim(comment) and app_private.grapheme_length(comment) between 1 and 500);
-- Preserve client review chronology while keeping immutable associations.
-- guard_record still supplies monotonically increasing server updated_at.
create or replace function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); op uuid; kind text; target uuid; action text;
  p jsonb; v jsonb; r jsonb; dep record; receipt app_private.sync_receipts;
  state app_private.sync_records; expected bigint; rev bigint; outcome jsonb;
  bathroom uuid; visit uuid; related uuid; dependency_state jsonb;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  perform app_private.sync_keys(command,array['operationId','entityType','entityId','type','payload','baseRevision','dependencies']);
  op := (command->>'operationId')::uuid; kind := command->>'entityType';
  target := (command->>'entityId')::uuid; action := command->>'type'; p := command->'payload';
  if op is null or target is null or kind is null or action is null
    or jsonb_typeof(command->'dependencies') is distinct from 'object' then
    raise exception 'Invalid command' using errcode='22023';
  end if;
  perform app_private.sync_revision();
  select * into receipt from app_private.sync_receipts where subject=actor and operation_id=op;
  if found then
    if receipt.request <> command then raise exception 'Operation ID reused' using errcode='22023'; end if;
    return receipt.outcome;
  end if;
  expected := (command->>'baseRevision')::bigint;
  for dep in select * from jsonb_each(command->'dependencies') loop
    select * into receipt from app_private.sync_receipts where subject=actor and operation_id=dep.key::uuid;
    if not found or receipt.outcome->>'status' <> 'acknowledged'
      or receipt.outcome->'revision' is distinct from dep.value then
      raise exception 'Invalid predecessor receipt' using errcode='22023';
    end if;
    -- Dependencies supply causal bases only for entities actually acknowledged.
    for dependency_state in select value from jsonb_array_elements(receipt.outcome->'entities') loop
      if dependency_state->>'entityType'=kind and dependency_state->>'entityId'=target::text then
        expected := greatest(expected,(dependency_state->>'revision')::bigint);
      end if;
    end loop;
  end loop;
  select * into state from app_private.sync_records where subject=actor and entity_type=kind and entity_id=target;
  if found and (state.deleted and kind<>'favourite' or expected is distinct from state.revision) then
    outcome := jsonb_build_object('subject',actor,'status','conflict','conflict',jsonb_build_object(
      'entityType',kind,'entityId',target,'revision',state.revision,'deleted',state.deleted,'payload',state.payload));
    insert into app_private.sync_receipts values(actor,op,command,outcome);
    return outcome;
  end if;
  if not found and expected is not null then raise exception 'Unknown base' using errcode='22023'; end if;

  if action in ('createBathroom','updateBathroom') and kind='bathroom' then
    perform app_private.sync_keys(p,array['id','name','normalized_name','creator','emoji','accent','provenance']);
    if (p->>'creator')::uuid is distinct from actor or (p->>'id')::uuid is distinct from target then
      raise exception 'Subject mismatch' using errcode='42501'; end if;
    if action='createBathroom' then
      insert into public.bathrooms(id,name,emoji,accent,contributor_id,account_private)
      values(target,p->>'name',p->>'emoji',(p->>'accent')::smallint,actor,true);
    else
      update public.bathrooms set name=p->>'name',emoji=p->>'emoji',accent=(p->>'accent')::smallint
        where id=target and contributor_id=actor and publication_status='pending';
      if not found then raise exception 'Ineligible proposal' using errcode='42501'; end if;
    end if;
  elsif action in ('createVisit','createVisitReview') then
    if action='createVisitReview' then
      if kind<>'review' then raise exception 'Wrong kind' using errcode='22023'; end if;
      perform app_private.sync_keys(p,array['visit','review']); v:=p->'visit'; r:=p->'review';
    else
      if kind<>'visit' then raise exception 'Wrong kind' using errcode='22023'; end if;
      v:=p;
    end if;
    perform app_private.sync_keys(v,array['id','bathroom','user','at','provenance']);
    bathroom:=(v->>'bathroom')::uuid; visit:=(v->>'id')::uuid;
    if (v->>'user')::uuid is distinct from actor or (action='createVisit' and visit is distinct from target) then
      raise exception 'Subject mismatch' using errcode='42501'; end if;
    if not exists(select 1 from public.bathrooms where id=bathroom and (publication_status='approved' or (contributor_id=actor and account_private)))
      or exists(select 1 from app_private.sync_records where entity_type='visit' and entity_id=visit and deleted) then
      raise exception 'Unavailable bathroom or removed visit' using errcode='42501'; end if;
    insert into public.visits(id,owner_id,bathroom_id,visited_at)
      values(visit,actor,bathroom,timestamptz 'epoch' + (v->>'at')::bigint * interval '1 microsecond');
  elsif action in ('createReview','updateReview') and kind='review' then
    perform app_private.sync_keys(p,array['review']); r:=p->'review';
  elsif action='deleteVisit' and kind='visit' then
    perform app_private.sync_keys(p,array['id','deletedReviewId']);
    if (p->>'id')::uuid is distinct from target or not exists(select 1 from public.visits where id=target and owner_id=actor) then
      raise exception 'Unavailable visit' using errcode='42501'; end if;
    select id into related from public.reviews where visit_id=target;
    -- Confirmation binds the exact child. A concurrently added/edited review is a conflict.
    if related is distinct from (p->>'deletedReviewId')::uuid then
      outcome := jsonb_build_object('subject',actor,'status','conflict','conflict',jsonb_build_object('entityType',kind,'entityId',target,
        'revision',state.revision,'deleted',false,'payload',state.payload));
      insert into app_private.sync_receipts values(actor,op,command,outcome); return outcome;
    end if;
    delete from public.visits where id=target and owner_id=actor;
  elsif action='setFavourite' and kind='favourite' then
    perform app_private.sync_keys(p,array['user','bathroom','value']);
    if (p->>'user')::uuid is distinct from actor or (p->>'bathroom')::uuid is distinct from target
      or jsonb_typeof(p->'value') is distinct from 'boolean' then
      raise exception 'Invalid favourite subject/state' using errcode='42501'; end if;
    if not exists(select 1 from public.bathrooms where id=target and (publication_status='approved' or (contributor_id=actor and account_private))) then
      raise exception 'Unavailable bathroom' using errcode='42501'; end if;
    if (p->>'value')::boolean then
      insert into public.favourites(owner_id,bathroom_id) values(actor,target) on conflict do nothing;
    else delete from public.favourites where owner_id=actor and bathroom_id=target;
    end if;
    -- Even false on an absent row has an acknowledged desired state.
    perform app_private.sync_emit('private',actor,'favourite',target,false,jsonb_build_object('value',(p->>'value')::boolean,'bathroom_id',target));
  else raise exception 'Unsupported command' using errcode='22023';
  end if;
  if r is not null then
    perform app_private.sync_keys(r,array['id','visit','bathroom','author','created','updated','rating','paper','hygiene','comfort','aesthetics','tags','comment','provenance']);
    if (r->>'author')::uuid is distinct from actor or (r->>'id')::uuid is distinct from target then
      raise exception 'Review subject mismatch' using errcode='42501'; end if;
    if action='createVisitReview' and ((r->>'visit')::uuid is distinct from visit or (r->>'bathroom')::uuid is distinct from bathroom) then
      raise exception 'Compound association mismatch' using errcode='22023'; end if;
    if not exists(select 1 from public.visits where id=(r->>'visit')::uuid and owner_id=actor and bathroom_id=(r->>'bathroom')::uuid) then
      raise exception 'Unavailable visit' using errcode='42501'; end if;
    if action='updateReview' then
      update public.reviews set rating=(r->>'rating')::numeric,paper=(r->>'paper')::smallint,
        hygiene=(r->>'hygiene')::smallint,comfort=(r->>'comfort')::smallint,aesthetics=(r->>'aesthetics')::smallint,
        tags=app_private.sync_tags(r->>'tags'),comment=r->>'comment',
        updated_at=timestamptz 'epoch' + (r->>'updated')::bigint * interval '1 microsecond'
        where id=target and author_id=actor and visit_id=(r->>'visit')::uuid and bathroom_id=(r->>'bathroom')::uuid;
      if not found then raise exception 'Immutable association or removed review' using errcode='42501'; end if;
    else
      insert into public.reviews(id,author_id,visit_id,bathroom_id,rating,paper,hygiene,comfort,aesthetics,tags,comment,created_at,updated_at)
      values(target,actor,(r->>'visit')::uuid,(r->>'bathroom')::uuid,(r->>'rating')::numeric,(r->>'paper')::smallint,
        (r->>'hygiene')::smallint,(r->>'comfort')::smallint,(r->>'aesthetics')::smallint,app_private.sync_tags(r->>'tags'),r->>'comment',
        timestamptz 'epoch' + (r->>'created')::bigint * interval '1 microsecond',
        timestamptz 'epoch' + (r->>'updated')::bigint * interval '1 microsecond');
    end if;
  end if;
  rev:=app_private.sync_revision();
  outcome:=jsonb_build_object('subject',actor,'status','acknowledged','revision',rev,'entities',
    (select jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'revision',revision,'deleted',deleted))
      from app_private.sync_records where subject=actor and revision=rev));
  insert into app_private.sync_receipts values(actor,op,command,outcome);
  return outcome;
end;
$$;

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
    'deleted',deleted,'payload',payload) order by position),'[]'::jsonb),coalesce(max(position),last_position)
  into result,last_position from (
    select * from app_private.sync_changes where sync_changes.feed=sync_pull.feed and subject=subject_id and position>last_position
    order by position limit page_size
  ) page;
  insert into app_private.sync_cursors(feed,subject,position) values(feed,subject_id,last_position) returning id into next_cursor;
  return jsonb_build_object('subject',case when feed='private' then subject_id else null end,
    'changes',result,'checkpoint',next_cursor,'reset',reset);
end;
$$;


revoke all on function app_private.valid_tag_emoji(text) from public,anon,service_role;
grant execute on function app_private.valid_tag_emoji(text),app_private.grapheme_length(text) to authenticated;
