# Backend portability, cost and local feasibility

Assessment date: 2026-11-25. **Documented** facts below come from current official sources. Procedures are **proposed and untested** unless the local evidence section explicitly says otherwise. No cloud account/project, remote deployment, paid resource, domain or hardware purchase was made. A real managed-to-self-hosted restore and post-migration login have **not** been performed.

## Managed Supabase Free: documented constraints

| Resource/condition | Current published Free allowance |
| --- | --- |
| Active projects | 2 |
| Database | 500 MB per project; shared CPU / 500 MB RAM |
| Auth | 50,000 monthly active users |
| Object storage | 1 GB; maximum upload 50 MB |
| Egress | 5 GB plus a separate 5 GB cached-egress allowance |
| Realtime / functions | 200 peak connections, 2 million messages/month; 500,000 function invocations |
| Backups / availability | No included automatic backups, PITR or uptime SLA |
| Inactivity | Projects pause after about one week of insufficient activity |

These are allowances, not a capacity forecast or a promise of permanent free hosting. “Unlimited API requests” does not remove resource limits. Paid plans, compute, larger database/storage, egress, Auth usage, Realtime, functions, image transformations, branching, PITR, custom domains, IPv4 and observability add-ons can create charges. Do not upgrade or enable paid add-ons automatically. Source: [current pricing and comparison](https://supabase.com/pricing).

Supabase currently documents a **one-year** window to resume a paused project in Studio. After that, available database/object backups must be downloaded before project deletion; deletion permanently removes backups too. Older 90-day articles are not the current policy. A paused service is an expected outage, not a reason to discard the local cache or queue. Sources: [current pausing guide](https://supabase.com/docs/guides/platform/free-project-pausing), [long-paused recovery](https://supabase.com/kb/troubleshooting/restore-project-after-90-days-pause).

Database quota exhaustion can put a project into read-only mode, so synchronization must retain writes locally and surface the restriction. Source: [database size and read-only mode](https://supabase.com/docs/guides/platform/database-size). Proposal: review usage monthly and before feature expansion, investigate at 70% of any relevant allowance, and choose data reduction, feature limits, local-only operation or a rehearsed move before exhaustion. Do not use artificial traffic as the availability strategy.

## Costs that survive a change of host

Supabase's built-in SMTP sends only to project-team addresses, currently limits delivery to two messages/hour and has no delivery SLA. Public email confirmation/recovery or magic links need separately configured SMTP. Delivery providers may require sender/domain verification and may later charge. A free SMTP integration is not a promise of free email delivery. Source: [SMTP restrictions and configuration](https://supabase.com/docs/guides/auth/auth-smtp).

Proposed cost controls: local mail capture for fictional PoC accounts; defer production email/provider choice. Evaluate an existing eligible sender or OAuth before any public signup promise, without requiring a paid domain. No SMS, paid SSO, media storage or image processing initially. Photos later add object capacity, backups, transfer/egress and moderation costs. Self-hosting avoids a mandatory Supabase subscription but still consumes electricity, network access, disk/backup capacity and maintenance time. Residential connectivity, CGNAT, TLS, dynamic addresses and availability must be assessed before public hosting; do not presume an existing Pi provides dependable public service or requires a new purchase now.

## Self-hosted Supabase feasibility

Official Docker requirements for the complete stack are at least 2 cores, 4 GB RAM and 40 GB SSD; recommended 4+ cores, 8+ GB RAM and 80+ GB SSD. Optional services may be removed to reduce requirements; reduced sizing must be measured. Use the manual, release-pinned setup rather than the upstream installer that installs Docker and changes group membership. Source: [Docker guide](https://supabase.com/docs/guides/self-hosting/docker).

An inexpensive x86_64 mini PC is a plausible future target; a Pi requires a 64-bit ARM OS, enough memory and durable storage. Upstream PostgreSQL publishes ARM builds, and the local runtime documents Linux amd64/arm64 support. Neither proves that every image in a selected self-hosted Compose release supports a particular Pi. Pin the release and inspect **all** selected image manifests for `linux/arm64` (including gateway, Studio, Auth, storage and optional helpers), then run the acceptance suite on that architecture. No Pi or full ARM stack has been tested here. Sources: [official PostgreSQL project](https://github.com/supabase/postgres), [runtime platform matrix](https://supabase.com/docs/guides/local-development/docker-and-native-runtimes). Current project flake outputs support only `x86_64-linux`; extending the development shell to ARM is separate from deploying upstream containers.

Self-hosting is one project configured largely through environment variables. Managed branching, managed backups/PITR, the Management API and several advanced metrics/analytics/ETL features are absent. Owner-managed hardening, upgrades, monitoring and restore drills replace platform operations. A CLI local stack is development-only, not a production self-hosted deployment. Source: [feature differences and responsibilities](https://supabase.com/docs/guides/self-hosting).

Minimize coupling by using ordinary PostgreSQL tables, constraints, indexes, RLS and small SQL commands. Keep Auth, API and object storage behind the boundaries in [architecture](architecture.md). Defer Realtime, Edge Functions, platform scheduling and extensions unless justified and available on the exit target. Plain PostgreSQL alone would not replace Supabase Auth/API/storage without additional work.

## Reproducible development environment — local evidence

The unchanged `flake.lock` pins nixpkgs revision `2786a2a72088ecf32aea5b3ec52099e6a7cff78f`. The optional `backend` shell in [flake.nix](../../flake.nix) adds Supabase CLI **2.111.0**, PostgreSQL client **17.12**, Podman **6.1.4** and podman-compose **1.6.0**. The existing default Flutter shell remains intact. No npm/global installation or system service is required to realize these tools:

```sh
nix develop .#backend --no-write-lock-file
command -v supabase psql podman podman-compose
bash tool/smoke_backend.sh
```

The shell was realized and CLI/help checked. Upstream currently advertises CLI 3.4.0; the existing lock supplies 2.111.0, so examples must be tested against the pinned CLI. In particular, the pinned dump command uses `--db-url`, whereas the current restore guide uses `--remote`. Do not copy new documentation flags into the old CLI or update the whole Flutter environment casually.

Existing host inspection: x86_64, about 21 GiB available memory and 128 GiB free disk at assessment time; rootless Podman works, cgroups v2, and `/etc/subuid`/`/etc/subgid` each assign `samuel:100000:65536`. Docker, Supabase CLI and PostgreSQL clients were absent from the original PATH; Compose is provided by the optional shell. Codex's filesystem sandbox initially prevented Podman writing `/run/user/1000/libpod` and blocked Nix's daemon socket. Authorized host execution of the same checks succeeded; that was a tool sandbox boundary, not missing NixOS configuration. No global NixOS/Home Manager edits or privileged service activation occurred.

The repeatable [smoke script](../../tool/smoke_backend.sh) uses the database image selected by official [self-hosted/v0.8.5 Compose](https://github.com/supabase/supabase/blob/self-hosted/v0.8.5/docker/docker-compose.yml): `supabase/postgres:17.6.1.136`, pinned to the tested amd64 digest in the script. It runs rootless with `--network none`, no published ports, random temporary credentials and disposable storage. It checks a fictional SQL insert, dump into a private temporary file, restore into a second database and exact restored identity/content; cleanup removes only its own container/anonymous volumes and temporary directory. **Passed locally on 2026-11-25**, with no test container left running. The first attempt failed because `public` already existed; the corrected dump uses `--clean --if-exists` only in these disposable databases. This is a **database-component smoke test**, not full Supabase API/Auth, a restore into an independent installation, or proof of the managed exit.

For a later full local stack, Supabase documents Podman as an alternative runtime. A foreground `podman system service --time=0 unix://<private-runtime-dir>/podman.sock` and `DOCKER_HOST=unix://<private-runtime-dir>/podman.sock` can supply the Docker API without enabling a privileged daemon; socket access grants control of that user's containers. Stop the process afterwards. Source: [CLI local setup](https://supabase.com/docs/guides/local-development/cli/getting-started). This socket/CLI-stack route was not executed here.

The pinned CLI's [gateway/Studio port bindings](https://github.com/supabase/cli/blob/v2.111.0/apps/cli-go/internal/start/start.go) and [database bindings](https://github.com/supabase/cli/blob/v2.111.0/apps/cli-go/internal/db/start/start.go) omit a host IP. Do not run its default stack on the assumption it is loopback-only. Before a full PoC, use a reviewed Compose configuration with all published ports explicitly bound to `127.0.0.1` (and no public IPv6 listener), or a proven equivalent network-isolated setup. Verify effective bindings before using credentials. Keep Auth, PostgreSQL and PostgREST only initially; optional Studio/mail capture must also remain local. Record all image digests separately from the Nix lock, which does not pin container downloads.

No additional owner system configuration is currently demonstrated as necessary for the network-disabled test. If the full rootless stack fails, capture the exact failure first. On a machine without Podman configured, the owner would need NixOS `virtualisation.podman.enable = true`, subordinate UID/GID mappings and usable rootless networking helpers, applied through their own system configuration. The flake supplies executables, not kernel/user-namespace permissions. Do not enable Docker/root services, open firewall ports or change global settings as an automated workaround.

## Proposed version-controlled schema and recovery materials

At Phase 2.1 create `supabase/migrations/<timestamp>_<purpose>.sql` for schema, constraints, grants, RLS, functions and their changes. Keep deterministic, explicitly fictional seeds separate and opt-in; never seed production community content from the Flutter samples. Test ordered migrations against an empty project and the preceding schema, including rollback/failure behavior. Do not modify Supabase-owned Auth/storage schemas directly. Capture service versions, extension inventory, configuration templates without secrets and image digests in the repository. Backups are data, not migrations.

Before real users, replace prototype-reset permission with tested non-destructive SQLite and PostgreSQL migrations. Reserve schema reset commands for named disposable environments. Keep secrets and operational exports outside the checkout in mode-0700 directories, with mode-0600 files and encrypted backup copies. Use explicit Git staging; never commit environment files, tokens, connection URLs with passwords, rclone credentials, signing keys, production dumps or logs containing credentials. Future tooling must add narrowly scoped ignore rules for its generated files before creating them; none of those files is required in this commit.

## Proposed managed-to-self-hosted runbook — not executed

1. Inventory managed PostgreSQL/Auth/storage versions, extensions, database roles, RLS/grants, SQL functions/triggers, auth providers, signing configuration, redirects, SMTP/templates, buckets and objects. Pin an official self-hosted release, compatible PostgreSQL major and exact image digests. Prove upgrade compatibility; SQL is not a guarantee of arbitrary cross-version restore. Provision only a local disposable target for rehearsal. Later public networking is a separate owner-approved operational decision.
2. Freeze writes during final export (retain offline mobile operations for replay after cutover), so roles/schema/data/object copies describe one consistent point. Export roles, schema and data separately through the CLI's Supabase-aware filters. Do not substitute a raw whole-platform `pg_dump`: it includes reserved internals. CLI dumps require a working compatible container API. Prefer direct or session-pooler connections, not a transaction pooler, and avoid requiring the paid IPv4 add-on. Source: [official platform-to-self-host restore](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

For pinned CLI 2.111.0 the command shapes are below. `SOURCE_DB_URL`/`TARGET_DB_URL` are placeholders to be supplied privately at execution time, not committed values. Do not enable shell tracing or paste secrets into shell history; a real automation wrapper must load them from protected files and redact diagnostics. Exports and restore below are **not validated** by the component smoke test:

```sh
umask 077
# Run in the private backup directory, outside the checkout.
supabase db dump --db-url "$SOURCE_DB_URL" --role-only --file roles.sql
supabase db dump --db-url "$SOURCE_DB_URL" --file schema.sql
supabase db dump --db-url "$SOURCE_DB_URL" --data-only --use-copy --file data.sql
psql -X --dbname "$TARGET_DB_URL" --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql --file schema.sql \
  --command 'SET session_replication_role = replica' --file data.sql
```

3. Before restoring, inspect dump scope: schema/data/roles/RLS plus `auth.users` and related auth data are documented as included. Verify actual row counts and fixtures rather than assuming a custom `--schema public` export contains Auth. Enable required extensions on the fresh target, restore with errors stopping the transaction, and check constraints/policies and orphan counts afterwards. Trigger suppression during import follows the official recipe and must never be exposed as an application capability. Preserve migrations/history appropriately; do not apply the initial schema twice.
4. Account portability: Supabase stores bcrypt hashes in `auth.users.encrypted_password`. Preserve IDs, hashes and related identity records through the supported export, not a CSV of public profiles. Never log password hashes. Same-password login on the new Auth server is an acceptance requirement, not yet verified. Source: [password storage](https://supabase.com/docs/guides/auth/password-security).
5. Generate destination API keys/signing secrets; configure the Flutter endpoint/client key for the destination. Current self-hosting also supports newer API/signing configurations; align the chosen release rather than assuming a managed key works locally. Plan to invalidate old access/refresh sessions and require fresh login; outstanding links/codes must be reissued. Configure Auth site URL, exact mobile/desktop redirects, OAuth provider secrets and provider-console callback URLs, SMTP host/credentials, sender, templates and rate limits separately. Test confirmation, reset and account linking if enabled. Do not copy passwords in plaintext or assume restoring users preserves active sessions. These settings are outside a SQL data dump. Source: [Auth/configuration caveats](https://supabase.com/docs/guides/self-hosting/restore-from-platform).
6. Storage is a separate migration: SQL bucket/object metadata is not the file bytes. Use the official S3/rclone copy approach where available, with a private temporary configuration and explicit source/destination buckets; fall back to authenticated Storage API list/download/upload if source S3 access is unavailable on the chosen plan. Preserve object keys, bucket visibility, content types and access policies; compare byte hashes/counts and test private access, signed URLs and public links. Reissue URL references for the new host. Avoid destructive `sync --delete` during rehearsal. Source: [object-copy guide](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3). No storage migration is tested here.
7. Produce an encrypted, checksummed recovery bundle containing SQL, objects, version manifest, non-secret configuration and separately protected recoverable secrets. Proposed cadence before production: daily backups while active, a backup before schema/service upgrades and monthly independent restore drills; retention and recovery objectives require owner approval. Free platform backup features cannot be the only recovery path. Store a second copy away from the running host using already available storage; do not require purchasing it now.
8. Validate the acceptance matrix below on an **independent** target, switch the configured endpoint only after success, then replay pending operations with their original IDs. Keep the source read-only for a bounded rollback period. Rollback after destination writes needs reconciliation/export of new writes, not merely switching URLs back. Record observed downtime, export/restore duration, data checks and target resources. Do not delete the source until the owner accepts the evidence.

## Migration acceptance gate before production users

This small PoC starts locally with fictional accounts A and B, then must eventually rehearse a real managed-Free-to-independent-self-hosted move with the same fixtures. Cloud project creation requires a later explicit task; it is not authorized here. A local-to-local rehearsal is useful but cannot satisfy the final managed exit gate.

| Check | Required evidence | Status |
| --- | --- | --- |
| Database component | Isolated official Postgres image, fictional insert/query/export/restore, no public ports, cleanup | Passed locally, 2026-11-25; scope limited as above |
| Database API | Version-controlled minimal bathroom/visit/review schema; anonymous catalogue read and authenticated write through the intended API, constraints rejecting invalid associations | Not run |
| Authentication | Create A/B through Auth, password login, refresh, logout/revocation, offline expired-session behavior; local mail capture if confirmation is enabled | Not run |
| Authorization | A/B each own visits and reviews; attempt direct HTTP read/update/delete and owner reassignment across users, anonymous private access, self-approval and privileged claims; verify rejection/no changes and own operations succeed | Not run |
| Public privacy | Published projections/aggregates work while pending/hidden data, emails, private visit IDs/times, favourites and joins stay inaccessible | Not run |
| Incremental operations | Duplicate request/restart/network loss, revision collision, delete versus stale update, late commit during pull and account switch; no duplicate/reappearing records or gaps | Not run |
| Fictional-data gate | Existing prototype sample/legacy records cannot be uploaded by association or retry; deliberately named PoC fixtures remain confined to test projects | Not run |
| Export | Capture source version/config manifest, filtered SQL including auth identities/hashes, RLS, fixture counts and object checksums; prove credentials/dumps stay outside Git | Not run |
| Independent restore | Fresh official self-hosted target, no shared volumes/source access; restore actual managed export, matching IDs/content/constraints/policies and object bytes | Not run |
| Login after migration | Disable source access; A and B log in at target with unchanged passwords and UUIDs; old tokens rejected, new sessions refresh; repeat two-user authorization tests | Not run |
| Enabled ancillary flows | Reconfigure/test OAuth callbacks, email confirmation/recovery, link reissue and object access if enabled; otherwise record disabled scope | Not run |
| Cutover/recovery | Flutter endpoint switch, preserve/replay offline queue, independent backup recovery and rollback rehearsal; record commands, versions, dates, timings and failures without secrets | Not run |

Until these gates pass and the owner approves production rules, managed Supabase is a **conditional candidate**, not a demonstrated portable production backend. Local behavior continues independently.

## Local verification for Phase 2.0

Formatting (44 Dart files unchanged), strict analysis with only the existing exact Material-import baseline, all **105 tests**, Linux debug build and Android debug APK build passed on 2026-11-25. No Flutter source/dependency/schema changes were made. The optional backend shell was realized; CLI version/init/dump help were checked. The isolated database-component smoke result and configuration checks are recorded with the completed milestone in [ROADMAP.md](../../ROADMAP.md). Full Auth/API/security/migration acceptance remains untested. Physical-phone acceptance of Session 4D remains pending.
