-- Phase 2.2C. A coarse writer lock deliberately trades throughput for a simple
-- commit-ordered watermark. No production retention/erasure policy is implied.
create table app_private.sync_clock (
  singleton boolean primary key default true check(singleton),
  revision bigint not null, transaction_id xid8
);
insert into app_private.sync_clock values(true,0,null);
create function app_private.sync_revision() returns bigint
language plpgsql volatile security definer set search_path = '' as $$
declare result bigint;
begin
  -- Row lock lasts through commit/rollback, including ordinary REST mutations.
  select revision into result from app_private.sync_clock where singleton for update;
  update app_private.sync_clock set
    revision = revision + case when transaction_id = pg_current_xact_id() then 0 else 1 end,
    transaction_id = pg_current_xact_id()
    where singleton returning revision into result;
  return result;
end;
$$;
create table app_private.sync_records (
  subject uuid not null, entity_type text not null, entity_id uuid not null,
  revision bigint not null, deleted boolean not null, payload jsonb not null,
  primary key(subject,entity_type,entity_id)
);
create table app_private.sync_changes (
  position bigint generated always as identity primary key,
  feed text not null check(feed in ('private','catalogue')), subject uuid not null,
  entity_type text not null, entity_id uuid not null, revision bigint not null,
  deleted boolean not null, payload jsonb not null,
  unique(feed,subject,entity_type,entity_id,revision)
);
create index sync_changes_scope on app_private.sync_changes(feed,subject,position);
create table app_private.sync_receipts (
  subject uuid not null references auth.users(id), operation_id uuid not null,
  request jsonb not null, outcome jsonb not null,
  primary key(subject,operation_id)
);
create table app_private.sync_cursors (
  id uuid primary key default gen_random_uuid(), feed text not null,
  subject uuid not null, position bigint not null,
  expires_at timestamptz not null default now() + interval '7 days'
);
create function app_private.sync_lock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin perform app_private.sync_revision(); return null; end;
$$;
create function app_private.sync_emit(f text, s uuid, t text, i uuid, d boolean, p jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare rev bigint := app_private.sync_revision();
begin
  if f = 'private' then
    insert into app_private.sync_records values(s,t,i,rev,d,p)
    on conflict(subject,entity_type,entity_id) do update
      set revision=excluded.revision,deleted=excluded.deleted,payload=excluded.payload;
  end if;
  insert into app_private.sync_changes(feed,subject,entity_type,entity_id,revision,deleted,payload)
  values(f,s,t,i,rev,d,p)
  on conflict(feed,subject,entity_type,entity_id,revision) do update
    set deleted=excluded.deleted,payload=excluded.payload;
end;
$$;
create function app_private.sync_capture() returns trigger
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
  perform app_private.sync_emit('private',subject_id,kind,record_id,gone and kind<>'favourite',
    case when kind='favourite' then jsonb_build_object('value',not gone,'bathroom_id',record_id)
      when gone then '{}'::jsonb else row_data end);
  if kind='bathroom' then
    public_payload := jsonb_build_object('id',record_id,'name',row_data->'name',
      'emoji',row_data->'emoji','accent',row_data->'accent',
      'institution',row_data->'institution','locality',row_data->'locality');
    if not gone and row_data->>'publication_status'='approved' then
      perform app_private.sync_emit('catalogue',catalogue,kind,record_id,false,public_payload);
    elsif (gone and exists(select 1 from app_private.sync_changes where feed='catalogue' and entity_type=kind and entity_id=record_id))
      or (tg_op='UPDATE' and old.publication_status='approved') then
      perform app_private.sync_emit('catalogue',catalogue,kind,record_id,true,
        case when gone then '{}'::jsonb else '{"_visibility":false}'::jsonb end);
    end if;
    -- Bathroom visibility affects published reviews too, without exposing visits.
    for r in select id from public.reviews where bathroom_id=record_id and published loop
      select to_jsonb(p) into public_payload from public.public_reviews() p where p.id=r.id;
      perform app_private.sync_emit('catalogue',catalogue,'review',r.id,public_payload is null,
        coalesce(public_payload,'{"_visibility":false}'::jsonb));
    end loop;
  elsif kind='review' then
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
-- BEFORE STATEMENT runs before row locks, avoiding row-lock/clock-lock inversion.
create trigger sync_lock_bathrooms before insert or update or delete on public.bathrooms for each statement execute function app_private.sync_lock();
create trigger sync_lock_visits before insert or update or delete on public.visits for each statement execute function app_private.sync_lock();
create trigger sync_lock_reviews before insert or update or delete on public.reviews for each statement execute function app_private.sync_lock();
create trigger sync_lock_favourites before insert or update or delete on public.favourites for each statement execute function app_private.sync_lock();
create trigger sync_capture_bathrooms after insert or update or delete on public.bathrooms for each row execute function app_private.sync_capture();
create trigger sync_capture_visits after insert or update or delete on public.visits for each row execute function app_private.sync_capture();
create trigger sync_capture_reviews after insert or update or delete on public.reviews for each row execute function app_private.sync_capture();
create trigger sync_capture_favourites after insert or update or delete on public.favourites for each row execute function app_private.sync_capture();

-- Existing rows are included in the initial replay. No private/public association.
do $$
declare r record;
begin
  for r in select * from public.bathrooms loop
    perform app_private.sync_emit('private',r.contributor_id,'bathroom',r.id,false,to_jsonb(r));
    if r.publication_status='approved' then
      perform app_private.sync_emit('catalogue','00000000-0000-0000-0000-000000000000','bathroom',r.id,false,
        jsonb_build_object('id',r.id,'name',r.name,'emoji',r.emoji,'accent',r.accent,'institution',r.institution,'locality',r.locality));
    end if;
  end loop;
  for r in select * from public.visits loop
    perform app_private.sync_emit('private',r.owner_id,'visit',r.id,false,to_jsonb(r));
  end loop;
  for r in select * from public.reviews loop
    perform app_private.sync_emit('private',r.author_id,'review',r.id,false,to_jsonb(r));
  end loop;
  for r in select * from public.favourites loop
    perform app_private.sync_emit('private',r.owner_id,'favourite',r.bathroom_id,false,to_jsonb(r));
  end loop;
  for r in select * from public.public_reviews() loop
    perform app_private.sync_emit('catalogue','00000000-0000-0000-0000-000000000000','review',r.id,false,to_jsonb(r));
  end loop;
end;
$$;

create function app_private.sync_keys(p jsonb, allowed text[]) returns void
language plpgsql set search_path = '' as $$
begin
  if jsonb_typeof(p) is distinct from 'object' or p - allowed <> '{}'::jsonb then
    raise exception 'Unexpected payload fields' using errcode='22023';
  end if;
end;
$$;
-- Local snapshots carry only emoji/label. Derive the server canonical key;
-- provenance is ignored and never establishes authenticity.
create function app_private.sync_tags(encoded text) returns jsonb
language plpgsql set search_path = '' as $$
declare item jsonb; result jsonb := '[]'; label text;
begin
  if jsonb_typeof(encoded::jsonb) is distinct from 'array' then
    raise exception 'Invalid tags' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(encoded::jsonb) loop
    perform app_private.sync_keys(item,array['emoji','label']);
    label:=lower(item->>'label');
    if label='grafiti' then label:='graffiti'; end if;
    result:=result || jsonb_build_array(item || jsonb_build_object('key',label,'version',1));
  end loop;
  return result;
end;
$$;
create function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); op uuid; kind text; target uuid; action text;
  p jsonb; v jsonb; r jsonb; dep record; receipt app_private.sync_receipts;
  state app_private.sync_records; expected bigint; rev bigint; outcome jsonb;
  bathroom uuid; visit uuid; related uuid; dependency_state jsonb;
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor) then
    raise exception 'Authenticated profile required' using errcode='42501';
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
      insert into public.bathrooms(id,name,emoji,accent,contributor_id)
      values(target,p->>'name',p->>'emoji',(p->>'accent')::smallint,actor);
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
    if not exists(select 1 from public.bathrooms where id=bathroom and publication_status='approved')
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
    if not exists(select 1 from public.bathrooms where id=target and publication_status='approved') then
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
        tags=app_private.sync_tags(r->>'tags'),comment=r->>'comment'
        where id=target and author_id=actor and visit_id=(r->>'visit')::uuid and bathroom_id=(r->>'bathroom')::uuid;
      if not found then raise exception 'Immutable association or removed review' using errcode='42501'; end if;
    else
      insert into public.reviews(id,author_id,visit_id,bathroom_id,rating,paper,hygiene,comfort,aesthetics,tags,comment)
      values(target,actor,(r->>'visit')::uuid,(r->>'bathroom')::uuid,(r->>'rating')::numeric,(r->>'paper')::smallint,
        (r->>'hygiene')::smallint,(r->>'comfort')::smallint,(r->>'aesthetics')::smallint,app_private.sync_tags(r->>'tags'),r->>'comment');
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

-- Review mutations invalidate visit deletion bases as well as review edit bases.
create function app_private.sync_review_parent() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v public.visits;
begin
  if tg_op='DELETE' then select * into v from public.visits where id=old.visit_id;
  else select * into v from public.visits where id=new.visit_id; end if;
  if found then perform app_private.sync_emit('private',v.owner_id,'visit',v.id,false,to_jsonb(v)); end if;
  return null;
end;
$$;
create trigger sync_review_parent after insert or update or delete on public.reviews for each row execute function app_private.sync_review_parent();

create function public.sync_pull(feed text, checkpoint uuid default null, page_size integer default 20) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  subject_id uuid; cursor_row app_private.sync_cursors; last_position bigint:=0;
  result jsonb; next_cursor uuid; reset boolean:=false;
begin
  if feed='private' then
    subject_id:=auth.uid();
    if subject_id is null or not exists(select 1 from public.profiles where id=subject_id) then
      raise exception 'Authenticated profile required' using errcode='42501'; end if;
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

-- No direct receipt, cursor, revision or log access. All helpers are private.
revoke all on all tables in schema app_private from public,anon,authenticated,service_role;
revoke all on all sequences in schema app_private from public,anon,authenticated,service_role;
revoke all on function app_private.sync_revision(),app_private.sync_lock(),app_private.sync_capture(),
  app_private.sync_emit(text,uuid,text,uuid,boolean,jsonb),app_private.sync_keys(jsonb,text[]),app_private.sync_review_parent()
  from public,anon,authenticated,service_role;
revoke all on function public.sync_submit(jsonb),public.sync_pull(text,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.sync_submit(jsonb) to authenticated;
grant execute on function public.sync_pull(text,uuid,integer) to anon,authenticated;

-- Identity resurrection is forbidden even through the original REST tables.
create function app_private.sync_no_resurrection() returns trigger
language plpgsql security definer set search_path = '' as $$
declare kind text:=case tg_table_name when 'bathrooms' then 'bathroom' when 'visits' then 'visit' else 'review' end;
begin
  if exists(select 1 from app_private.sync_records where entity_type=kind and entity_id=new.id and deleted) then
    raise exception 'Removed identity' using errcode='23514'; end if;
  return new;
end;
$$;
create trigger sync_no_resurrection_bathrooms before insert on public.bathrooms for each row execute function app_private.sync_no_resurrection();
create trigger sync_no_resurrection_visits before insert on public.visits for each row execute function app_private.sync_no_resurrection();
create trigger sync_no_resurrection_reviews before insert on public.reviews for each row execute function app_private.sync_no_resurrection();
create function app_private.sync_profile_projection() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select * from public.public_reviews() where author_id=new.id loop
    perform app_private.sync_emit('catalogue','00000000-0000-0000-0000-000000000000','review',r.id,false,to_jsonb(r));
  end loop;
  return null;
end;
$$;
create trigger sync_lock_profiles before update on public.profiles for each statement execute function app_private.sync_lock();
create trigger sync_profile_projection after update on public.profiles for each row execute function app_private.sync_profile_projection();
revoke all on function app_private.sync_tags(text),app_private.sync_no_resurrection(),app_private.sync_profile_projection() from public,anon,authenticated,service_role;
