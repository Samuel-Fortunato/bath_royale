# Phase 2.1A — Local Supabase proof of concept

This isolated environment contains **fictional prototype data only**. Supabase/PostgreSQL is accepted for this bounded PoC. Production hosting remains conditional on Phase 2.1B's independent full-stack restore and Phase 2.1C's actual managed-Free exit rehearsal, including unchanged-password login. Neither gate is passed by these local tests. No Flutter authentication, networking, synchronization, account association or SQLite change is included.

## Run locally

Use the existing rootless Podman setup and optional locked Nix shell from the repository root:

```sh
nix develop .#backend --no-write-lock-file
python3 backend/poc.py start
python3 backend/poc.py status
python3 backend/poc.py test
python3 backend/poc.py measure
ruff check backend
ruff format --check backend
python3 backend/poc.py stop
```

`start` validates Compose, creates private disposable credentials, waits for readiness, applies ordered migrations transactionally and checks their SHA-256 history on subsequent starts. It does not reset data. `migrate` applies outstanding migrations explicitly. `test` starts the environment if needed, signs up/logs in the two fictional accounts, loads the separate [fixtures](../../backend/fixtures.sql) and exercises the authorization matrix. Tests reset records belonging to these dedicated fictional accounts inside this isolated project; do not repurpose it for genuine data. They leave a useful sample with approved and pending proposals, varied identities/ratings/tags, public reviews, private repeat/unreviewed visits and favourites. The public fixture names/comments are Portuguese (Portugal).

For a deliberate destructive reset of **this PoC only**:

```sh
python3 backend/poc.py clean
python3 backend/poc.py test
```

`stop` retains volumes and credentials. `clean` removes only the `bath-royale-poc` Compose project's containers, network, named volumes and its three known credential files. It does not prune images or other projects. No reset/recovery runs automatically after errors. Missing credentials with an existing database volume cause startup to fail; recover the private state or explicitly clean the fictional environment.

Credentials are generated with Python's cryptographic RNG under `${XDG_STATE_HOME:-$HOME/.local/state}/bath-royale-poc/` (directory 0700, files 0600). `secrets.json` and `compose.env` contain runtime passwords/signing material; `accounts.json` contains disposable `example.invalid` email/password accounts. Access/refresh tokens remain in process memory. Never print expanded Compose configuration, environment values, raw Auth responses or container inspection environments. The wrapper captures subprocess output and suppresses it on failure; normal test diagnostics contain labels/status codes, never credentials. PostgreSQL statement/error-statement logging is disabled, Auth logs only errors and PostgREST logs only critical failures. As with any local container setup, the owner of the rootless runtime can inspect its secrets.

The APIs are separate local endpoints: Auth `http://127.0.0.1:55431`, PostgREST `http://127.0.0.1:55432`. Authenticated database requests use an Auth-issued bearer JWT. Anonymous catalogue reads need no API key in this direct local configuration. No gateway/API-key authentication layer is claimed here. PostgreSQL has no published port; SQL checks use `podman exec`. All published bindings explicitly use IPv4 loopback, with no IPv6/public listener. The dedicated internal Podman network prevents external delivery; SMTP also points at a closed container-local port. No cloud project, external SMTP, system service, privileged container or global configuration change is needed.

## Pins and minimal service selection

[Compose](../../backend/compose.yml) is a reduced configuration derived from the official [self-hosted/v0.8.5 release](https://github.com/supabase/supabase/blob/self-hosted/v0.8.5/docker/docker-compose.yml). It retains ordinary Supabase PostgreSQL, GoTrue/Auth and PostgREST, sufficient to retain Auth identities/password hashes, SQL schema/grants/RLS and API configuration for the next portability stage. Studio, gateway, analytics, storage, Realtime, functions and pooler are omitted. Object storage will need a separately pinned fixture/service if introduced for the later restore gate.

The locked CLI remains available but does not orchestrate this stack: its pinned start implementation omits an explicit host IP on published ports (see [portability](portability.md)). A small reviewed Compose subset gives explicit loopback bindings and fewer services without needing a Docker socket/service. This is a development environment, not a production self-hosted deployment.

| Component | Version | Pinned image SHA-256 |
| --- | --- | --- |
| Supabase PostgreSQL | 17.6.1.136 (server PostgreSQL 17.6) | `5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b` |
| Supabase Auth | v2.198.0 | `5e9ee59d7406d21412b35e6b524a1f2004ff518a0b49fa3cc08dee75811af09d` |
| PostgREST | v14.18 | `c7cd7e265a85b05248abf53f4473fcec7e327c282d0bd0cf60f1551996d09fcf` |

Only x86_64 Linux/amd64 was executed. Do not assume these digests or the current Nix flake support ARM. Nix lock revision remains `2786a2a72088ecf32aea5b3ec52099e6a7cff78f`: CLI 2.111.0, PostgreSQL client 17.12, Podman 6.1.4, podman-compose 1.6.0, Python 3.14.10 and Ruff 0.17.4. Python/Ruff are added only to the optional backend shell. The default Flutter shell and dependency lockfiles are unchanged. Containers/volumes/network all have dedicated `bath-royale-poc` names; no automatic restart policy or host socket is needed.

## Provisional fictional-product assumptions

These are implementation assumptions for this PoC, **not final product decisions**:

- Anyone can browse approved catalogue entries, public usernames and explicitly published review projections.
- Authenticated users own private visits/favourites and author-only review records. Reviews default to unpublished and can be explicitly published/unpublished by their author for an approved bathroom. Repeat visits can each have one optional review.
- There are no private bathrooms. A pending/rejected contribution is a proposal visible only to its contributor and protected moderators. Contributors can edit pending proposals and remove eligible unpublished proposals. Approved entries cannot be edited/deleted by their contributor through the API.
- Moderator membership is provisioned only through administrative SQL in this isolated test. Moderators can approve another contributor's pending proposal through a small audited function; they cannot approve their own. No moderation UI, reward system or general administrative API exists.
- Public review identity is a fictional username plus author UUID. The projection deliberately has no dates at all; public identity/date policy remains undecided. Profile data contains no email or private preferences.
- Email/password signup is auto-confirmed locally, with no email delivery. Production signup, confirmation/recovery, OAuth, cloud-backup consent, moderation/author-edit policy and account deletion remain open. This fixture setup is unsuitable for genuine users.

## Schema and authorization

The [initial SQL migration](../../supabase/migrations/202611250001_core.sql) creates public profiles, bathrooms with curated emoji/accent identity, private visits, individual reviews with version-1 JSON tag snapshots and optional comments, and private favourites. Profiles reference `auth.users`; Auth's private tables are neither modified by application migrations nor exposed by PostgREST. Institution/locality, original contributor/origin, publication and verification are separate columns. No Official/Community or inside/outside enum finalizes classification.

UUID defaults, foreign keys, a composite review-to-visit foreign key, unique visit association, exact visit uniqueness, rating/content checks, timestamps and lookup indexes enforce relationships. The composite foreign key requires the same author and bathroom as the associated visit. Deleting one's visit cascades its optional review, retaining independent favourites. Review/visit identity, ownership, creation time and associations are immutable; updates receive server timestamps. Favourites use an immutable owner/bathroom primary key.

All exposed tables enable RLS and explicitly replace permissive Supabase default grants with allowlists. Insert-column grants exclude ownership/IDs/timestamps; `auth.uid()` supplies ownership, and RLS validates it. Update-column grants and immutable triggers provide separate guards. Ordinary clients cannot set publication/verification/approval metadata, contributor origin or moderator membership. The protected moderator predicate uses the authenticated subject, ignoring user-editable Auth metadata.

Raw reviews are author-only, including their private visit foreign key. `public_reviews()` is an explicit fixed-column, read-only projection over published reviews and approved bathrooms, joined only to public profiles. It includes review/bathroom/author IDs, username, original score scales, tag snapshots and comment. It has no email, visit ID, visit date, creation/update date, favourites or private history. Public catalogue foreign-key embedding still requires child-table grants and RLS; a public parent does not authorize private child rows. The definer projection intentionally bypasses author-only RLS for its exact allowlist; it has no arbitrary SQL/filter arguments. Both it and `approve_bathroom(uuid)` have fixed empty search paths, fully qualified references and explicit execute grants. Helpers and the moderator table live in an unexposed schema. Runtime bootstrap also removes the upstream image's `supabase_admin` membership from `authenticator`.

### Content-length and Unicode limits

Flutter remains the authoritative local UX implementation: 100 bathroom-name graphemes, 30 tag-label graphemes, 500 comment graphemes, ten distinct tag labels and one emoji grapheme per tag. The PoC server uses a **conservative codepoint bound**, not equivalent extended-grapheme counting: PostgreSQL `char_length` limits names/labels/comments to 100/30/500 Unicode codepoints. This cannot admit more than the corresponding grapheme limit, but can reject valid Flutter input containing combining marks or long emoji sequences. For example, 251 decomposed `e` + combining acute graphemes count as 502 codepoints and are rejected as a comment; 500 single-codepoint toilet emoji are accepted. No Flutter transport is connected, so this mismatch affects only PoC API clients. Resolve it with a reviewed Unicode-aware validator or an approved shared limit before integration; do not claim parity.

Tags contain exactly `emoji`, `label`, `key`, `version`. The server checks count, required JSON types, version 1, normalized label shape, canonical lowercase keys, the grafiti/graffiti alias and duplicate label keys independently of emoji. Its deliberately bounded emoji subset permits one base with optional selector/modifier, ZWJ sequences, paired regional flags and keycaps up to 16 codepoints. Tests include families, skin tones, flags, hearts and keycaps, and reject multiple unrelated emoji/isolated modifiers/half flags. This is not a complete Unicode emoji/grapheme implementation. Canonicalization uses PostgreSQL lowercase and whitespace checks, not a promise of identical Dart behavior for every Unicode case. Review comments are plain text, not threads or HTML; no content moderation policy is implied.

## Verification evidence and limitations

Executed on 2026-11-25; concrete results and resource measurements follow below. The automated [authorization suite](../../backend/tests/authorization.py) uses real Auth signup/password login/refresh/logout and PostgREST HTTP calls with A/B access tokens, plus `SET LOCAL ROLE` SQL checks. Privileged SQL is limited to fictional fixtures/moderator provisioning, structural inspection and transactional-rollback/trigger checks; it is not used as proof that client authorization works.

It verifies anonymous catalogue/projection reads, anonymous private/write rejection, own CRUD, private cross-user read/update/delete isolation, public review author isolation, immutable ownership/associations, duplicate review/visit/favourite rejection, mismatched visit/bathroom/author rejection, invalid numeric/content/tag rejection, proposal privacy, self-approval and metadata/JWT privilege attacks, real moderator approval, public projection column allowlists, private-data exclusion and FK embedding. It also checks zero scores, optional/repeat visits, review unpublication, cascading visit deletion and independent favourites. SQL checks cover grants/RLS, function search paths, trigger protection and rollback without a partial table.

Logout globally revokes the user's refresh sessions and Auth rejects the revoked session. PostgREST independently validates signed JWTs; an already-issued JWT can still authorize database requests until expiry plus clock skew. Tests verify both this residual access and eventual HTTP 401. The configured lifetime is 60 seconds; [PostgREST v14.18 source](https://github.com/PostgREST/postgrest/blob/v14.18/src/PostgREST/Auth/Jwt.hs) allows 30 seconds of skew. Tests wait up to 100 seconds and emit progress while waiting. This matches the distinction documented in [Supabase sessions](https://supabase.com/docs/guides/auth/sessions); no immediate database-JWT revocation mechanism is claimed. No Flutter offline/session behavior is implemented or verified.

During development the first expiry assertion allowed only 75 seconds and failed; it now accounts for the pinned implementation's skew. An initial guessed Auth image tag was unavailable; the selected tag was then read directly from the official pinned release and resolved to the digest above. The sandbox blocked Podman's per-user runtime and Flutter telemetry writes; host execution using the existing rootless/Nix environment succeeded, with no system-level blocker or configuration change. No tokens/secrets were printed during diagnosis.

Phase 2.1B must still export/restore the full selected stack into an independent target with unchanged-password login; Phase 2.1C must still rehearse the actual managed-Free exit. Storage/object portability, ARM, production hardening/email/erasure/moderation, Flutter integration, provenance/upload gates, durable synchronization and concurrency/conflict behavior remain unverified or deferred. The local catalogue fixtures do not constitute a production seed.

### Recorded results — 2026-11-25

- Clean stack: **232 Auth/API/SQL assertions passed**, including actual signup of A/B. Existing-account reruns retain their private credentials rather than recreating Auth identities. The suite takes about two minutes, principally waiting for real token expiry.
- Explicit stop/start: **passed**; all fixture counts and visit UUIDs, credentials and the single applied migration/checksum were unchanged. Retained sample: two profiles, four bathrooms (three approved, one pending), three visits, two published reviews and two favourites. The migration itself seeds no catalogue rows.
- Rootless/loopback checks: **passed** for all three unprivileged containers; only `127.0.0.1:55431` and `127.0.0.1:55432` published. The network is dedicated and internal. Project cleanup from the earlier disposable instance completed successfully before the clean verification.
- After restart, a 10-second idle CPU delta measured PostgreSQL **0.261%**, Auth **0.005%**, PostgREST **0.082%** of one core (about **0.35%** combined). Memory was **63.09 / 10.71 / 14.65 MB**, approximately **88 MB** combined; the immediate post-test sample was approximately **140 MB** combined. These are small local samples, not production sizing or a hardware-capacity guarantee.
- Uncompressed image sizes: database **1,270,450,762 bytes**, Auth **63,011,989 bytes**, API **21,557,876 bytes**; approximately **1.36 GB** combined before layer sharing. PostgreSQL data files used **42 MiB**, including initialization/WAL; the application database size was **10,849,427 bytes**. Allow additional space for writable layers, Nix tools/cache, upgrades and later export copies. This reduced PoC does not need the complete upstream service set.
- Extension inventory from the selected database: `pg_stat_statements:1.11`, `pgcrypto:1.3`, `plpgsql:1.0`, `supabase_vault:0.3.1`, `uuid-ossp:1.1`. Application SQL adds no extra extension dependency beyond the supplied UUID/Auth facilities.
- **105 Flutter tests passed**, with unchanged Flutter source/dependencies/SQLite; formatting (44 files unchanged), the exact existing Material-import analysis gate and Linux/Android debug builds passed. Python Ruff lint/format, Compose parsing, Nix flake evaluation and actionlint passed. No hosted compilation result is inferred from these checks.
