-- OPT-IN FICTION ONLY. Not a migration or a genuine production catalogue seed.
insert into public.bathrooms
  (id, name, emoji, accent, institution, locality, origin, contributor_id,
   publication_status, verification_status, approved_by, approved_at)
select '10000000-0000-4000-8000-000000000001', 'Trono de teste — universidade fictícia',
  '📚', 1, 'Universidade Fictícia', 'Cidade Imaginária', 'contribution', a.id,
  'approved', 'verified', b.id, now()
from public.profiles a cross join public.profiles b
where a.username = 'poc_fictional_a' and b.username = 'poc_fictional_b'
on conflict (id) do nothing;
insert into public.bathrooms
  (id, name, emoji, accent, locality, origin, contributor_id,
   publication_status, approved_by, approved_at)
select '10000000-0000-4000-8000-000000000002', 'Coroa de teste — jardim imaginário',
  '🌿', 3, 'Cidade Imaginária', 'curated', b.id, 'approved', a.id, now()
from public.profiles a cross join public.profiles b
where a.username = 'poc_fictional_a' and b.username = 'poc_fictional_b'
on conflict (id) do nothing;
