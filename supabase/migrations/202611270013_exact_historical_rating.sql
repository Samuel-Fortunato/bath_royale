-- A4: unrelated edits preserve exact server numeric precision, not just client doubles.
create or replace function public.sync_submit(command jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); receipt app_private.sync_receipts; op uuid; action text:=command->>'type';
 translated jsonb; outcome jsonb; score numeric; old_score numeric; keep_score boolean:=false;
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
  perform app_private.sync_keys(command->'payload',array['review','preserveRating']);
  if command->'payload' ? 'preserveRating' then
   if jsonb_typeof(command->'payload'->'preserveRating')<>'boolean' then raise exception 'Invalid rating preservation flag' using errcode='22023'; end if;
   keep_score:=(command->'payload'->>'preserveRating')::boolean;
  end if;
  select rating into old_score from public.reviews where id=(command->>'entityId')::uuid and author_id=actor;
 end if;
 if keep_score then
  if old_score is null then raise exception 'Owned historical review required' using errcode='42501'; end if;
  score:=old_score;
 end if;
 if score is null or (score is distinct from old_score and (score<1 or score>5 or score<>trunc(score))) then
  raise exception 'Choose an integer rating from 1 to 5' using errcode='22023';
 end if;
 translated:=jsonb_set(command,'{type}',to_jsonb(left(action,length(action)-2)));
 if action='updateReviewV2' then
  translated:=jsonb_set(translated,'{payload}',(translated->'payload')-'preserveRating');
  if keep_score then translated:=jsonb_set(translated,'{payload,review,rating}',to_jsonb(old_score)); end if;
 end if;
 outcome:=app_private.a31_sync_submit(translated);
 update app_private.sync_receipts set request=command where subject=actor and operation_id=op;
 return outcome;
end; $$;
