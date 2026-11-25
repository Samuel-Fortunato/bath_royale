-- Phase 2.1A fictional PoC. No catalogue fixtures or production policy decisions.
create schema app_private;
revoke all on schema app_private from public, anon, authenticated;
revoke create on schema public from public, anon, authenticated;
-- Supabase images grant permissive defaults; explicitly remove them for our objects.
alter default privileges in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key default auth.uid() references auth.users(id),
  username text not null unique check (username ~ '^[a-z][a-z0-9_]{2,29}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table app_private.moderators (
  user_id uuid primary key references auth.users(id)
);
create function app_private.is_moderator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from app_private.moderators where user_id = auth.uid());
$$;
grant usage on schema app_private to authenticated;
grant execute on function app_private.is_moderator() to authenticated;

create table public.bathrooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (name = btrim(name) and char_length(name) between 1 and 100),
  emoji text not null default '🚽' check (emoji in ('🚽','👑','📚','🌿','🔧','🌈','🏛️','🧪')),
  accent smallint not null default 0 check (accent between 0 and 5),
  -- Exploratory descriptive metadata, not an Official/Community classification.
  institution text check (char_length(institution) between 1 and 100),
  locality text check (char_length(locality) between 1 and 100),
  origin text not null default 'contribution' check (origin in ('contribution','curated')),
  contributor_id uuid not null default auth.uid() references public.profiles(id),
  publication_status text not null default 'pending' check (publication_status in ('pending','approved','rejected')),
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified')),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((publication_status = 'approved') = (approved_by is not null and approved_at is not null)),
  check (approved_by is null or approved_by <> contributor_id)
);
create index bathrooms_publication on public.bathrooms(publication_status);
create index bathrooms_contributor on public.bathrooms(contributor_id);
create table public.visits (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id),
  bathroom_id uuid not null references public.bathrooms(id),
  visited_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, bathroom_id, visited_at),
  unique (id, owner_id, bathroom_id)
);
create index visits_owner_chronology on public.visits(owner_id, visited_at desc);
create index visits_bathroom on public.visits(bathroom_id);

create function app_private.valid_tags(tags jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  item jsonb; label text; canonical text; seen text[] := '{}';
  base text := '[🀀-🇥🈀-🏺🐀-🫿☀-➿©®‼⁉™ℹ⌚⌛⌨⏏⏩-⏺]';
begin
  if jsonb_typeof(tags) <> 'array' then return false; end if;
  if jsonb_array_length(tags) > 10 then return false; end if;
  for item in select value from jsonb_array_elements(tags) loop
    if jsonb_typeof(item) <> 'object' or not (item ?& array['emoji','label','key','version'])
       or (select count(*) from jsonb_object_keys(item)) <> 4
       or jsonb_typeof(item->'label') <> 'string' or jsonb_typeof(item->'emoji') <> 'string'
       or jsonb_typeof(item->'key') <> 'string' or item->'version' <> '1'::jsonb then return false; end if;
    label := item->>'label';
    if char_length(label) not between 1 and 30 or label <> btrim(label)
       or label ~ '[\n\r,]' or label ~ '[[:space:]]{2}' then return false; end if;
    canonical := lower(label);
    if canonical = 'grafiti' then canonical := 'graffiti'; end if;
    if item->>'key' <> canonical or canonical = any(seen) then return false; end if;
    -- Conservative subset: single base/modifier/VS, ZWJ sequence, flag or keycap.
    -- Not a complete Unicode grapheme validator (see docs).
    if char_length(item->>'emoji') not between 1 and 16
       or ((item->>'emoji') !~ ('^' || base || '️?[🏻-🏿]?(‍' || base || '️?[🏻-🏿]?)*$')
           and (item->>'emoji') !~ '^[🇦-🇿]{2}$'
           and (item->>'emoji') !~ '^[#*0-9]️?⃣$')
       then return false; end if;
    seen := array_append(seen, canonical);
  end loop;
  return true;
end;
$$;
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles(id),
  visit_id uuid not null unique,
  bathroom_id uuid not null references public.bathrooms(id),
  rating numeric not null check (rating between 0 and 5),
  paper smallint not null check (paper between 0 and 2),
  hygiene smallint not null check (hygiene between 0 and 4),
  comfort smallint not null check (comfort between 0 and 4),
  aesthetics smallint not null check (aesthetics between 0 and 4),
  tags jsonb not null default '[]' check (app_private.valid_tags(tags)),
  comment text check (char_length(comment) between 1 and 500 and comment = btrim(comment)),
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (visit_id, author_id, bathroom_id) references public.visits(id, owner_id, bathroom_id) on delete cascade
);
create index reviews_author on public.reviews(author_id);
create index reviews_public on public.reviews(bathroom_id) where published;
create table public.favourites (
  owner_id uuid not null default auth.uid() references public.profiles(id),
  bathroom_id uuid not null references public.bathrooms(id),
  created_at timestamptz not null default now(),
  primary key (owner_id, bathroom_id)
);
create index favourites_bathroom on public.favourites(bathroom_id);

create function app_private.guard_record() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if (to_jsonb(new) - array['updated_at','username','name','emoji','accent','institution','locality','publication_status','verification_status','approved_by','approved_at','visited_at','rating','paper','hygiene','comfort','aesthetics','tags','comment','published'])
       is distinct from
       (to_jsonb(old) - array['updated_at','username','name','emoji','accent','institution','locality','publication_status','verification_status','approved_by','approved_at','visited_at','rating','paper','hygiene','comfort','aesthetics','tags','comment','published']) then
      raise exception 'Immutable identity or association' using errcode = '23514';
    end if;
    new.updated_at := greatest(old.updated_at, clock_timestamp());
  end if;
  return new;
end;
$$;
create trigger guard_profiles before update on public.profiles for each row execute function app_private.guard_record();
create trigger guard_bathrooms before update on public.bathrooms for each row execute function app_private.guard_record();
create trigger guard_visits before update on public.visits for each row execute function app_private.guard_record();
create trigger guard_reviews before update on public.reviews for each row execute function app_private.guard_record();

alter table public.profiles enable row level security;
alter table public.bathrooms enable row level security;
alter table public.visits enable row level security;
alter table public.reviews enable row level security;
alter table public.favourites enable row level security;
alter table app_private.moderators enable row level security;
create policy profiles_read on public.profiles for select to anon, authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy bathrooms_read on public.bathrooms for select to anon, authenticated
 using (publication_status = 'approved' or contributor_id = (select auth.uid()) or (select app_private.is_moderator()));
create policy bathrooms_insert on public.bathrooms for insert to authenticated
 with check (contributor_id = (select auth.uid()) and publication_status = 'pending' and origin = 'contribution'
   and verification_status = 'unverified' and approved_by is null and approved_at is null);
create policy bathrooms_update on public.bathrooms for update to authenticated
 using (contributor_id = (select auth.uid()) and publication_status = 'pending')
 with check (contributor_id = (select auth.uid()) and publication_status = 'pending');
create policy bathrooms_delete on public.bathrooms for delete to authenticated
 using (contributor_id = (select auth.uid()) and publication_status in ('pending','rejected'));
create policy visits_read on public.visits for select to authenticated using (owner_id = (select auth.uid()));
create policy visits_insert on public.visits for insert to authenticated
 with check (owner_id = (select auth.uid()) and exists (select 1 from public.bathrooms b where b.id = bathroom_id and b.publication_status = 'approved'));
create policy visits_update on public.visits for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy visits_delete on public.visits for delete to authenticated using (owner_id = (select auth.uid()));
create policy reviews_own on public.reviews to authenticated using (author_id = (select auth.uid()))
 with check (author_id = (select auth.uid()) and (not published or exists (select 1 from public.bathrooms b where b.id = bathroom_id and b.publication_status = 'approved')));
create policy favourites_own on public.favourites to authenticated using (owner_id = (select auth.uid()))
 with check (owner_id = (select auth.uid()) and exists (select 1 from public.bathrooms b where b.id = bathroom_id and b.publication_status = 'approved'));

-- Explicit allowlists, including insert columns: ownership and timestamps are server-derived.
revoke all on public.profiles, public.bathrooms, public.visits, public.reviews, public.favourites from public, anon, authenticated, service_role;
grant select on public.profiles, public.bathrooms to anon, authenticated;
grant insert(username), update(username) on public.profiles to authenticated;
grant insert(name,emoji,accent,institution,locality), update(name,emoji,accent,institution,locality), delete on public.bathrooms to authenticated;
grant select, delete on public.visits, public.reviews, public.favourites to authenticated;
grant insert(bathroom_id,visited_at), update(visited_at) on public.visits to authenticated;
grant insert(visit_id,bathroom_id,rating,paper,hygiene,comfort,aesthetics,tags,comment,published),
 update(rating,paper,hygiene,comfort,aesthetics,tags,comment,published) on public.reviews to authenticated;
grant insert(bathroom_id) on public.favourites to authenticated;
grant execute on function app_private.valid_tags(jsonb) to authenticated;

-- Deliberately small audited public projection. No visit/auth join or arbitrary query argument.
create function public.public_reviews() returns table (
  id uuid, bathroom_id uuid, author_id uuid, username text,
  rating numeric, paper smallint, hygiene smallint, comfort smallint, aesthetics smallint,
  tags jsonb, comment text
) language sql stable security definer set search_path = '' as $$
  select r.id, r.bathroom_id, r.author_id, p.username, r.rating, r.paper, r.hygiene,
         r.comfort, r.aesthetics, r.tags, r.comment
  from public.reviews r join public.bathrooms b on b.id = r.bathroom_id
  join public.profiles p on p.id = r.author_id
  where r.published and b.publication_status = 'approved';
$$;
revoke all on function public.public_reviews() from public, anon, authenticated, service_role;
grant execute on function public.public_reviews() to anon, authenticated;

create function public.approve_bathroom(proposal_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not app_private.is_moderator() then
    raise exception 'Moderator required' using errcode = '42501';
  end if;
  update public.bathrooms set publication_status = 'approved', approved_by = auth.uid(), approved_at = now()
    where id = proposal_id and publication_status = 'pending' and contributor_id <> auth.uid();
  if not found then raise exception 'Ineligible proposal' using errcode = '42501'; end if;
end;
$$;
revoke all on function public.approve_bathroom(uuid) from public, anon, authenticated, service_role;
grant execute on function public.approve_bathroom(uuid) to authenticated;

-- Trigger helpers are not remotely callable. The moderator predicate reveals only own membership.
revoke all on function app_private.guard_record() from public, anon, authenticated, service_role;
revoke all on function app_private.valid_tags(jsonb) from public, anon, service_role;
revoke all on function app_private.is_moderator() from public, service_role;
grant execute on function app_private.is_moderator() to anon;
