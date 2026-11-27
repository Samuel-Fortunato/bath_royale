-- A persisted source xid may coincide with a future destination transaction ID.
-- Require a transaction-local marker too, so the first restored writer always
-- advances the clock. No epoch reset, receipt or cursor invalidation is needed.
create or replace function app_private.sync_revision() returns bigint
language plpgsql volatile security definer set search_path = '' as $$
declare result bigint; marker text:=current_setting('bath.sync_revision',true);
begin
  select revision into result from app_private.sync_clock where singleton for update;
  update app_private.sync_clock set
    revision = revision + case when transaction_id=pg_current_xact_id() and marker=revision::text then 0 else 1 end,
    transaction_id=pg_current_xact_id()
    where singleton returning revision into result;
  perform set_config('bath.sync_revision',result::text,true);
  return result;
end;
$$;
