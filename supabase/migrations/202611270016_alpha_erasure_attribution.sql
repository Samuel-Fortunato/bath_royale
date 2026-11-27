-- Owner-only erasure changes attribution, never bathroom identity or public data.
-- The guard is restored in the same transaction; any error rolls back the DDL.
do $migration$
declare definition text;
begin
 select pg_get_functiondef('app_private.erase_alpha_domain(uuid)'::regprocedure) into definition;
 if position('update public.bathrooms set contributor_id=null' in definition)=0 then raise exception 'Erasure source mismatch'; end if;
 definition:=replace(definition,'update public.bathrooms set contributor_id=null','alter table public.bathrooms disable trigger guard_bathrooms; update public.bathrooms set contributor_id=null');
 definition:=replace(definition,'delete from app_private.reports where reporter=actor;','alter table public.bathrooms enable trigger guard_bathrooms; delete from app_private.reports where reporter=actor;');
 execute definition;
end; $migration$;
