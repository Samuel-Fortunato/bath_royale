# Phase 2.1C — Managed migration rehearsal

Status on 2026-11-26: **authorized, preflight in progress; managed exit gate not passed**.
The owner created the dedicated fictional-data **Bath Royale Test** project on Free,
Frankfurt, reference `eiitfxbmavmqafqwfxiy`. This authorizes only this test project.
No Phase 2.2 or Flutter backend integration is included.

## Verified preflight

- Both supplied JSON configuration files exist outside Git, have mode 0600 and
  contain their required fields. Contents are never printed.
- The configured API origin and IPv4 session-pooler database username identify
  the expected project; the pooler uses port 5432.
- The endpoint responds, but libpq certificate verification against the system
  CA bundle fails with an untrusted certificate chain. This does not demonstrate
  invalid database credentials. No database query or mutation has succeeded in
  this rehearsal yet. The owner's earlier PostgreSQL 17.12/aarch64 observation
  remains owner-reported, pending independent verification.
- HTTPS Auth settings report signup enabled and email autoconfirm disabled;
  `/auth/v1/health` reports **v2.199.0**. No signup was attempted, avoiding email.
- The locked backend shell supplies Supabase CLI **2.111.0** and PostgreSQL
  client **17.12**. Local Auth remains pinned to **v2.198.0** and PostgreSQL to
  **17.6**. Compatibility is not inferred from adjacent versions.

## Required dashboard preparation

In this project only, open [Database Settings](https://supabase.com/dashboard/project/eiitfxbmavmqafqwfxiy/database/settings),
SSL Configuration, and download the server root certificate. Save it as
`~/.local/state/bath-royale-cloud-test/root.crt`. The certificate is public;
credentials remain private. The wrapper uses `sslmode=verify-full` and this CA
without changing global trust configuration. See [official SSL instructions](https://supabase.com/docs/guides/database/psql).

Under Authentication → Sign In / Providers → Email, disable **Confirm email**
for this fictional project. The public Auth API must report
`mailer_autoconfirm=true` before signup. This permits the supported signup API
without an admin secret or email delivery. Production confirmation/recovery
remains deferred; do not reuse this setting as production policy.

Run the read-only reusable preflight from the checkout:

```sh
nix develop .#backend --offline --no-write-lock-file -c python3 backend/cloud.py
```

The wrapper rejects unexpected origins, database users/ports, non-private JSON
files and symlinks. It forces TLS verification regardless of URL query options,
loads passwords through libpq environment variables rather than process arguments,
passes SQL on stdin, and suppresses raw subprocess/HTTP errors. Its version and
row-count output is non-sensitive. A passing preflight is not export/restore proof.

## Remaining execution procedure — not yet executed

Follow the [official platform-to-self-hosted restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform),
checked on 2026-11-26. It describes three Supabase-aware exports and one fail-fast
transactional restore. Its current `--remote` examples must be adapted to the
locked CLI's supported `--db-url`; do not update the Nix lock just to copy flags.

1. Verify TLS and expected project before every remote mutation. Inventory all
   non-platform schemas/tables and Auth users, aborting on unrelated application
   data. Apply version-controlled migrations with checksum tracking; preserve
   explicit grants, policies, protected ownership and projections. Account for
   managed event triggers and restricted administrator privileges.
2. Provision fictional A/B through Auth with confirmation disabled, privately
   retain original passwords, then exercise the existing two-user matrix using
   the publishable key and real sessions. Freeze test writers before export;
   never upload Flutter SQLite records.
3. Export roles, schema and COPY data with Supabase CLI filtering. Do not reuse
   the local-only allowlist as the managed backup scope. Inspect every nonempty
   COPY section, including Auth tables; preserve UUIDs and password hashes.
   Keep SQL, diagnostics and manifests under a mode-0700 directory outside Git,
   files mode 0600. Record actual commands without credentials, versions,
   timings, sizes, SHA-256 checksums and row counts. These measurements are
   currently absent, not zero.
4. Bootstrap a third independent rootless local installation, disjoint from
   both preserved Phase 2.1A/B stacks, with fresh credentials/signing secret and
   exclusively loopback API bindings. Inventory Auth schema/columns and
   extensions before restore. Explicitly explain any compatibility edits;
   never drop populated Auth sections to hide incompatibility. Restore roles,
   schema and data in one transaction with errors stopping and trigger
   suppression limited to import. Keep target Auth/API stopped during import.
5. Before fixture mutations, compare complete application rows, Auth UUIDs and
   password hashes privately; compare constraints, functions, grants and RLS,
   and revalidate foreign keys. Demonstrate original-password login for A/B,
   destination refresh and rejection of still-valid source JWTs and source
   refresh sessions. Restart independently and compare persistence. Only then
   run the authorization fixture matrix on the destination.
6. Publish only non-sensitive evidence, actual resource measurements and
   failures/corrections. Mark the managed exit gate passed only after every
   required managed export, independent restore, login and authorization check
   succeeds. Keep the managed project and prior local environments intact.

## Explicitly unverified/deferred

ARM hardware execution; object storage (unused); production confirmation,
recovery and SMTP; encrypted off-host backups; public networking and production
hardening; Flutter endpoint switching and durable offline queue replay;
production moderation/privacy/erasure policy. This rehearsal's permission-protected
local exports will not by themselves constitute encrypted disaster recovery.
No plan upgrade, paid add-on, additional managed project, organization change,
GitHub deployment connection or managed-project deletion is authorized.

## Session handoff

The owner requested ending this session while locating the two dashboard controls.
No remote mutation, schema deployment, account provisioning, export or restore
was performed. The managed gate remains unpassed. Ruff lint/format, three Python
unit tests (including negative destination/TLS/file-permission checks), Dart
formatting/strict analysis and all 105 Flutter regressions pass for this preflight
unit. The first sandboxed Flutter invocation failed on its existing telemetry
file permissions; the authorized host rerun passed. Builds were not repeated:
Flutter source, dependencies and runtime behavior are unchanged. Previous full
build evidence remains at Phase 2.1B, not a new build claim for this session.
