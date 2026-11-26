# Phase 2.1C — Managed migration rehearsal

Status on 2026-11-26: **managed exit rehearsal passed for the tested scope; production acceptance deferred**.
The owner authorized only the dedicated fictional-data **Bath Royale Test** project
on Free, Frankfurt, reference `eiitfxbmavmqafqwfxiy`. No Phase 2.2, production hosting
acceptance or Flutter integration is implied.

## Resumption and Auth discrepancy

Resumed from clean commit `dcab016`. The live project was independently inspected
before mutation: PostgreSQL **17.12**, zero Auth users, no non-platform application
relations, and only `api.json`, `connection.json`, `root.crt` in its private state.
The root certificate was already present; verified TLS through the IPv4 session
pooler succeeded with `sslmode=verify-full`. Existing credentials were reused.

The existing preflight passed before any code change. The live settings response
contains **`disable_signup: false` and `mailer_autoconfirm: true`, both JSON
booleans**. `external` is an object; `phone_autoconfirm` is a separate boolean and
is not evidence about email. The previous report was stale: its recorded
`mailer_autoconfirm=false` is not reproducible now. There is no retained historical
response proving whether propagation or some other cause explained that report.
No dashboard change, admin confirmation or confirmation email was needed here.

Previously, `.get()` plus `is True`/`is False` would print a missing or mistyped
field as false. The preflight now rejects absent/non-boolean flags explicitly.
Regression tests cover missing, null, numeric and string values. This fixes an
ambiguity in reporting without asserting it caused the earlier discrepancy.
The signup wrapper rechecks the explicit boolean flags before **each** signup.
Do not change production email policy based on this fictional test configuration.

## Commands, credentials and preservation

Use the existing lock, without global configuration changes:

```sh
nix develop .#backend --offline --no-write-lock-file
python3 backend/cloud.py
# Opt-in managed fixture deployment/matrix; resets only its fictional sample:
python3 backend/cloud_rehearsal.py
```

`cloud.py` is read-only. `cloud_rehearsal.py` validates existing account identities
and private permissions, refuses unrelated relations in the application schemas
and unrelated Auth users, applies versioned SQL with checksum tracking and runs
the managed two-user matrix. It is **not** the export/restore command and should
not run concurrently with a snapshot. Initial inventory also inspected relations
outside the application schemas and found no unrelated non-platform data.

The managed matrix passed **231 assertions**. The managed long-lived JWT expiry
wait was explicitly omitted, without changing its configuration or bypassing
signature/authorization checks; refresh, logout, revoked Auth sessions and
residual valid API JWT behavior were exercised. The destination retains the full
60-second expiry plus clock-skew test. Managed Auth health was **v2.199.0**;
local Auth remains **v2.198.0**. No source-session/signing secrets were copied.

Credentials and exports remain outside Git under
`~/.local/state/bath-royale-cloud-test/`, directory 0700, files 0600. No service-role
or management token was needed. Database passwords travel through libpq environment
variables, not CLI arguments. SQL diagnostics, rows, password hashes and tokens
are never public evidence. The permission-protected bundle is not an encrypted
backup and contains sensitive Auth information.

## Actual export and restore

The [official platform restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform)
was checked again on 2026-11-26. The locked CLI **2.111.0** accepts `--db-url`, not
the guide's `--remote`. For roles, schema and COPY data respectively, the actual
procedure generated scripts with:

```sh
supabase db dump --db-url postgresql://postgres:placeholder@127.0.0.1:5432/postgres --dry-run --role-only
supabase db dump --db-url postgresql://postgres:placeholder@127.0.0.1:5432/postgres --dry-run
supabase db dump --db-url postgresql://postgres:placeholder@127.0.0.1:5432/postgres --dry-run --data-only --use-copy
```

These contain no real credentials. Only generated `export PG...` lines were
removed; the remaining CLI `pg_dump`/`sed` filters ran unchanged through Bash with
the verified libpq environment and locked host PostgreSQL client **17.12**. This
avoids Docker-socket setup and credential-bearing arguments while retaining
Supabase's platform exclusions. It does not substitute the local-only allowlist.
The database/API endpoint target was checked through the existing preflight.

The managed fixture writer finished before export; no concurrent test writer was
run. Complete rows were compared again against the source before destination
login. This is a quiescent dedicated-fictional-project rehearsal, not a production
maintenance lock against arbitrary writers. Flutter SQLite data was never uploaded.

The private bundle is `export-1795662128304479868`. It retains original roles,
schema and data exports, generated CLI scripts, every COPY section/count, complete
private before/after rows, source/target Auth columns and inventories, adapted SQL,
compatibility decisions, diagnostics, execution scripts, manifest and evidence.
The executed Python scripts are retained there; `/tmp` copies are disposable.
The manifest records byte sizes and SHA-256 for every evidence file and is checked
before completion. No original export is overwritten by an adaptation.

The third independent rootless installation uses `POC_INSTANCE=cloud-destination`,
project `bath-royale-poc-cloud-destination`, Auth/API ports **55451 / 55452** bound
exclusively to **127.0.0.1**, its own network, volumes and private state. No host
DB port, shared source volume or global system service is used. Both Phase 2.1A/B
installations remain untouched. Pins remain PostgreSQL **17.6.1.136 / server 17.6**,
Auth **v2.198.0**, PostgREST **v14.18**; see [exact digests](local-poc.md).
Fresh runtime credentials and JWT secret are generated independently.

Target Auth first bootstrapped its own schema/migrations; Auth/API were stopped
for import. Roles, schema and adapted COPY data restored in **one fail-fast
transaction**, with trigger suppression local to import. Compatibility decisions:

- All populated application and Auth identity sections were retained, including
  complete `auth.users` and `auth.identities` rows/password hashes.
- Two source sessions, two refresh tokens and two session AMR claims were
  deliberately excluded to require fresh authentication, independently of schema
  compatibility. No MFA factors existed. Original session rows remain in the
  original export; active-session portability is not claimed.
- Only **empty** incompatible sections were omitted: `auth.custom_oauth_providers`
  and the nine Storage sections listed in private `compatibility.json`. Storage
  has no objects/buckets and is not enabled in the reduced target.
- The managed Realtime-only `GRANT SET ON PARAMETER log_min_messages TO
  supabase_realtime_admin` was omitted because the reduced target has no such
  role/service. The first restore rolled back on that missing role.
- Managed platform roles/memberships, Auth migration versions, PostgreSQL patch
  version/architecture and Vault extension **0.3.2 vs 0.3.1** differ. Application
  records do not use Vault. These are inventoried, not claimed identical.
- Target creator default privileges added extra table/column grants during
  restore. They were explicitly revoked and the **source ACLs** replayed for
  tables, columns, functions and schemas. The managed event-helper function's
  implicit default EXECUTE grant was also reproduced. The managed event trigger
  itself is excluded by CLI filtering; application tables retain explicit RLS.
  Do not treat a plain successful SQL import as sufficient authorization proof.

## Preservation and verification

Before destination fixture mutations, complete rows matched exactly: **2 Auth
users, 2 identities, 2 profiles, 4 bathrooms, 3 visits, 2 reviews, 2 favourites,
1 moderator and 1 migration/checksum**. This includes UUIDs, hashes, ownership,
relationships, content and timestamps. Application schemas/tables, functions,
triggers, policies, constraints and table/column grants matched. Effective
function ACLs were separately compared. Definitions were deparsed with an empty
search path on both sides to avoid qualification-only differences (`auth.uid()`
versus `uid()`, and `auth.users` versus `users`); no broad textual normalization
was applied. Each imported foreign key was dropped/re-added within a rolled-back
transaction to validate actual rows.

Original-password A/B login preserved UUIDs; destination refresh succeeded;
still-unexpired managed access JWTs and managed refresh tokens were rejected.
An independent target stop/start preserved complete rows and login identity.
Only then did the full destination fixture matrix run with signup disabled.
The managed project and earlier local environments are preserved. Destination
fixture mutations intentionally change only its own sample after preservation.

### Final measurements and checks

The destination completed **226 authorization/authentication assertions**, including
real expiry, after all preservation/login/restart checks. The manifest and evidence
were written before the owner's PC crash; resumption verified their checksums.
Post-crash unchanged-password/UUID login also passed, and the destination was
stopped again. No fixture reset was needed to recover.

Filtered export: **19.114 s**; successful transactional restore: **0.187 s**.
These exclude bootstrap, inspection, ACL reconciliation and all verification.
Immediately after restart the destination DB/Auth/API used **65.95 / 13.03 /
14.13 MB** (about **93 MB** total). Instantaneous CPU samples were **10.18 /
5.75 / 1.66%**, startup-biased rather than steady-state capacity estimates.

| Original export | Bytes | SHA-256 |
| --- | ---: | --- |
| `roles.sql` | 370 | `168a95a9c745af5ed4679751f90419ac9dc434240a213b03e32a06d5664c2308` |
| `schema.sql` | 23,529 | `7e4a756c86ca0403991b956ff53518b94630edf4fef8e472f90922028f7da543` |
| `data.sql` | 18,719 | `a370832d589cae7307cf1bba9672285de334bdf561cc64de8866dc24933e59c2` |

Permission-protected manifests cover both original and adapted files. Failed
checks were retained: an initial compatibility check mistakenly required target
application tables before schema import; the check was corrected without writes.
The Realtime role failure rolled back. Preservation checks then detected extra
default grants and a missing implicit function ACL; these were corrected and
all comparisons repeated before fixture testing. An initial unit-test invocation
missed `PYTHONPATH`; the successful command sets it inside the Nix shell.

Local final code/build verification is recorded in the roadmap. No remote CI
success is inferred from local tests. Production acceptance remains separate.

## Deferred decisions and operations

No paid plan/add-on, domain, additional project/hardware, organization change,
GitHub deployment connection or project deletion occurred. ARM execution, object
storage, production SMTP/confirmation/recovery, encrypted off-host backups, public
networking/hardening, operational ownership/RPO/RTO/cost limits, moderation/privacy
and Flutter endpoint/offline-queue integration remain deferred. No Phase 2.2 work
is authorized by this rehearsal.

To inspect or restart the preserved third target, use the locked backend shell:

```sh
POC_INSTANCE=cloud-destination python3 backend/poc.py status
POC_INSTANCE=cloud-destination python3 backend/poc.py start
POC_INSTANCE=cloud-destination python3 backend/poc.py stop
```

Do not run `test` or another restore to inspect preserved data. Repeating the
rehearsal requires an explicitly disposable fresh target; no automatic reset,
pruning, source cleanup or database-error recovery deletion is implemented.
