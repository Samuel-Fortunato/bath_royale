# Phase 2.1B — Independent local portability rehearsal

This is a local-to-local rehearsal with fictional A/B accounts. It does **not** prove a managed Supabase exit, ARM support or production readiness. Phase 2.1C needs separate owner authorization. No Flutter integration, cloud account, public service or object storage is introduced.

## Commands and isolation

From the checkout, using the committed Nix lock:

```sh
nix develop .#backend --offline --no-write-lock-file
python3 backend/migration.py
```

The source must already contain the Phase 2.1A fictional A/B accounts and sample records. The rehearsal refuses a missing account file or an existing destination volume. It never seeds or runs the destructive authorization fixtures on the source. On a new disposable source only, `python3 backend/poc.py test` can create the sample; do not run it merely to prepare a migration of existing data.

One [Compose template](../../backend/compose.yml) and [lifecycle implementation](../../backend/poc.py) serve both installations:

| Resource | Source | Destination |
| --- | --- | --- |
| Project/container prefix | `bath-royale-poc` | `bath-royale-poc-destination` |
| Auth/API loopback ports | 55431 / 55432 | 55441 / 55442 |
| Named volumes | `<prefix>-db-data`, `<prefix>-db-config` | distinct destination prefix |
| Internal network | `<prefix>-network` | distinct destination prefix |
| Private state directory | `$XDG_STATE_HOME/bath-royale-poc` | `$XDG_STATE_HOME/bath-royale-poc-destination` |

`XDG_STATE_HOME` defaults to `$HOME/.local/state`. Directories are 0700 and generated files 0600, outside Git. Destination database/Auth/API passwords and JWT signing secret are generated independently. Only the fictional login credentials are reused to test unchanged-password login; no runtime secrets or source sessions are copied. Database ports are not published; both APIs bind exclusively to `127.0.0.1`. Effective bindings and rootless operation are checked.

The source is stopped for validation and left intact, with all volumes and private files retained. To resume it later:

```sh
POC_INSTANCE=source python3 backend/poc.py start
```

To inspect/stop or explicitly remove **only** the disposable destination:

```sh
POC_INSTANCE=destination python3 backend/poc.py status
POC_INSTANCE=destination python3 backend/poc.py stop
POC_INSTANCE=destination python3 backend/poc.py clean
```

After a failed or completed rehearsal, explicitly clean the destination before repeating `python3 backend/migration.py`. There is no automatic cleanup, database reset, pruning or source deletion. Export directories remain private for inspection and are not removed by lifecycle cleanup.

## Logical export and restore boundary

[The automated procedure](../../backend/migration.py) performs these ordered steps, failing on any mismatch:

1. Start the source without resetting records and independently bootstrap the target from the same pinned images, allowing Auth to create its own platform schema/migrations. Do **not** apply application migrations there yet.
2. Log in existing A/B on the source, then snapshot every row (including Auth hashes privately). Measure both running installations. Stop source Auth/API writers before the dumps; the DB has no external listener. This provides a quiescent export for this bounded stack, not a general production write-lock mechanism.
3. Run the image's ordinary `pg_dump` (PostgreSQL 17.6) through `podman exec`, with `--no-owner`, separately exporting:
   - Application schema: `--schema-only --clean --if-exists --schema=public --schema=app_private --schema=bath_royale_migrations`.
   - Data via COPY: `--data-only`, with explicit `--table` selections for `auth.users`, `auth.identities`, all five application tables, `app_private.moderators` and `bath_royale_migrations.applied`.
4. Save SQL, non-secret Compose template, component/lock manifest and an inventory of schemas, roles/attributes/memberships, extensions, policies, table/column grants, RLS flags, constraints, triggers, function definitions and Auth migration versions. Generate byte sizes and SHA-256 checksums in `manifest.json`; verify all exported files before restore.
5. Stop **all** source containers and verify their stopped state. Stop destination Auth/API while restoring. Run `psql -X -qAt -v ON_ERROR_STOP=1` as `supabase_admin` with one transaction containing schema SQL, `SET LOCAL session_replication_role=replica`, data SQL and commit. A failure rolls back the transaction. The clean/drop statements are restricted to the named disposable destination application schemas.
6. Compare all restored rows exactly, including UUIDs, password hashes, ownership, relationships, timestamps, content and migration checksums, without printing any row or hash. Compare the structural inventory. Re-add every restored foreign key within a rolled-back transaction to force validation over existing data; explicitly check review/visit/owner/bathroom orphan counts. COPY still enforces checks and uniqueness. One known equivalent nested-AND formatting change in the comment CHECK is normalized narrowly; all other definitions compare verbatim.
7. Start destination normally. Imported application migration history causes the initial migration to be checked/skipped, not applied twice. The target's independently created Auth history must match the source exactly.
8. Before any fixture reset, log in A/B with their original passwords and unchanged UUIDs, refresh new sessions and use them through PostgREST. Require source access JWTs to still be unexpired when rejected with HTTP 401; source refresh tokens must fail. Restart the destination and compare complete rows again, then log in again.
9. **Only after preservation assertions pass**, run the existing full authorization matrix on the disposable destination with signup disabled. This test resets its fictional application fixtures; it does not recreate migrated Auth accounts. The original restored state was already compared before these intentional test mutations.

Roles are inventoried rather than blindly restored with source login passwords: this stack uses only the upstream predefined roles plus grants/membership wiring, independently initialized on the target and compared exactly. There are no custom login roles to migrate. Extensions and Auth schema are independently created by the same pins and checked; only required Auth identity data crosses the boundary. Sessions, refresh tokens, audit/session-flow tables and platform-owned schemas are deliberately excluded. Migrating identities is separate from migrating active sessions: users sign in afresh, without password resets or manual account recreation. OAuth, email links and recovery are disabled/unverified.

The export directory is reported under the private source state as `export-<unique-number>`. It contains sensitive SQL including password hashes; never print, commit or publish it. The local plain-text bundle is permission-protected, **not encrypted disaster recovery**. It requires a separate encrypted backup policy before genuine data. `evidence.json` contains only counts, checksums, timings and resource metrics.

## Versions, evidence and limits

The unchanged pins are Supabase PostgreSQL **17.6.1.136 / PostgreSQL 17.6**, Auth **v2.198.0**, PostgREST **v14.18**, with the exact amd64 digests in [the PoC runbook](local-poc.md#pins-and-minimal-service-selection) and exported component manifest. Nix supplies Podman **6.1.4**, podman-compose **1.6.0**, Python **3.14.10**, Ruff **0.17.4**, CLI **2.111.0** and host PostgreSQL client **17.12**. The actual dump/restore use the database image's matched 17.6 tools. No flake or global configuration changes are needed.

This resembles the managed runbook's separate schema/data exports, Auth identities, destination credentials and post-cutover checks, but uses an explicit reviewed allowlist instead of the Supabase CLI's managed-platform filters. It does not dump reserved managed internals or copy a volume. Managed source privileges, role/extension/version differences, additional Auth tables/providers, network/pooler access, CLI filtering, service configuration and actual managed-Free export remain Phase 2.1C work. Production write freezing/cutover, encrypted off-host backups, rollback after target writes, Flutter endpoint/queue changes, production hardening and ARM hardware are unverified. Object storage is not selected: its metadata, bytes, policies and URL portability remain **untested**.

Failed attempts: an initial comparison took the Auth snapshot before source login updated its timestamp; snapshot timing was corrected. A later inventory check identified pg_dump flattening an equivalent nested AND in one CHECK; the specific expression is now normalized and constraints are still independently revalidated. A diagnostic attempt to repeat restore into the already restored target failed on the existing user primary key and rolled back; retries require explicit destination cleanup rather than duplicate imports.

A clean rerun also exposed an initialization readiness race before restore: the database image can expose a temporary initialization server before final bootstrap completes. Startup now waits for TCP readiness and both required runtime roles before configuring their passwords. The destination alone was explicitly cleaned for retries.

## Recorded results — 2026-11-26

The final complete run passed all preservation, authentication, restart and structural checks, followed by **226 authorization/authentication assertions**. Compared with the clean Phase 2.1A run (232), signup and missing-profile creation are omitted because identities/profiles already exist; the attack matrix is retained.

Export **5.454 s**; transactional restore **0.597 s** (excluding bootstrap and verification). Checksums below identify this particular private export; repeated pg_dump runs include generated framing and Auth login timestamps, so hashes need not repeat.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `components.json` | 877 | `c9c85567028aab0d6d825c56288e70d03e12067ecfa47067d5913287d5b5dde4` |
| `compose.yml` | 3108 | `1a71678b71f8c9c2c958f6645eef321730055f4566230ca23e4c2bd5673999e6` |
| `data.sql` | 7625 | `063a97e271ab0f2ba68547ee55ab2631ab14cbcaf747997f4f02c09ea34ddea1` |
| `inventory.json` | 38400 | `919741b92d22705f22db94122dc385923b07a3d94cb162f0a3eb0777a5be2a79` |
| `schema.sql` | 33603 | `cae82b6f85d830691ae9f4f08d659f49eb5dcd31ba879e3bc85a466d37451fa2` |

Exact comparison: 2 Auth users, 2 identities, 2 profiles, 4 bathrooms, 3 visits, 2 reviews, 2 favourites, 1 moderator and 1 application migration/checksum. Auth migration versions, roles/memberships, extensions, schema/RLS/grants, functions, triggers and constraints matched. No password reset or account recreation occurred.

While both installations ran: source DB/Auth/API **65.54 / 11.30 / 17.43 MB**, destination **66.73 / 11.26 / 12.86 MB**, approximately **185 MB combined**. Podman instantaneous CPU samples were approximately **0.79 / 0.17 / 0.11%** and **14.90 / 1.56 / 1.25%**, respectively, while the destination had just initialized; these are startup-biased samples, not steady-state sizing. No ARM or production-capacity conclusion follows.

Verification also passed Ruff lint/format, checksum corruption/missing-file tests, actionlint, documentation links, all **105 Flutter regressions**, Dart formatting/strict analysis and Linux/Android debug builds. Flutter sources, dependencies and SQLite behavior are unchanged.

Final inspection confirmed disjoint mounted volumes/networks and private bundle permissions. Both installations are left stopped with their volumes/credentials retained; the source was not cleaned. The destination authorization suite intentionally leaves its own sample after preservation checks.
