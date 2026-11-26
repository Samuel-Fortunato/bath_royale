# Roadmap

The phases describe intended sequencing, not a fixed specification. Unconfirmed details are proposals and may change with product decisions and implementation findings. Check items only when implemented and verified.

## Phase 0 — Development environment (completed)

- [x] Configure the project Nix flake and direnv integration.
- [x] Establish a Flutter development environment and complete Linux debug and release builds.

## Phase 1 — Complete the local prototype (completed)

- [x] Audit the existing prototype and fix bugs, including review updates, favourite filtering and unreviewed bathroom presentation.
- [x] Investigate the Flutter 3.50 Material deprecation; document migration considerations.
- [x] Separate bathroom entities from individual reviews and define local ownership and visit semantics.
- [x] Implement bathroom details.
- [x] Create and edit reviews while preserving the rating descriptions.
- [x] Create bathrooms with appropriate validation.
- [x] Improve search, sorting, filters and favourites.
- [x] Persist local data and define a migration strategy.
- [x] Implement local personal/community rankings and expand the visit-based collection.
- [x] Add automated tests for models, state and important user flows.
- [x] Verify formatting, analysis, tests and appropriate builds; update documentation.

## CI/CD milestone — Android previews (completed, between Phase 1 and Phase 2)

- [x] Verify GitHub Actions using the locked Nix/Flutter/Android environment, formatting, precise Material-deprecation handling and automated tests.
- [x] Verify an installable APK artifact from an actual successful GitHub Actions run on `main`, with manual dispatch, dependency caching, minimal permissions and 14-day retention.
- [x] Compare the existing Android installation's identity/certificate with the local development key and configure the approved key as a GitHub Actions secret.
- [x] Verify predictable preview versioning and APK signing; provide automatic GitHub development pre-release distribution.
- [x] Document phone installation, data-preserving update requirements and automatic verified commits/pushes.

See [Android preview operations](docs/android-previews.md). Production signing and store release preparation remain open. This milestone does not start backend implementation.

Verified on 2026-11-25: local formatting, strict analysis, all 40 tests, actionlint, Nix flake checks and Android preview compilation pass. [The first GitHub Actions run](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45604860872) independently passed the checks, built APK version `0.1.0-preview.1` / code `1001`, verified the existing signing certificate and uploaded the APK/checksum artifact. Automatic draft-first publication is verified by hosted run 45724799545 and its publication-only retry; preview 1015 downloads, checksum, package, version and signing certificate were independently checked. See the operations document for details. A physical in-place installation of the CI APK remains a separate device check.

## Phase 1.6 — Approved UI/UX redesign (before Phase 2)

The [design specification](docs/bath-royale-design/ui-design.md) and [interactive reference](docs/bath-royale-design/ui-reference.html) are the approved direction. Sessions 1–3 established the layout. Session 4A adds persistent visual identities and refines experiences; 4B will extend the visual language to the remaining destinations. Preserve ownership, ranking formulas and backend scope.

### Session 1 — Application shell, Explore and bathroom details

- [x] Contextual destination titles, preserved tab state, accessible Profile → Settings theme control and shared Material typography/card hierarchy; retain both existing palettes.
- [x] One grouped filter panel, active removable chips/count, all existing search/sort/filter options, and visit-derived discovery filters.
- [x] Compact neutral cards with primary community score/count, secondary personal rating, discovery status and independent favourite hearts throughout the app.
- [x] Independent Summary, Reviews and Personal Visits tabs; numeric community category means with original scales, latest reviewed personal experience by visit chronology, and lazy independent histories.
- [x] Immediate visit registration with a celebratory invitation, separately positioned undo/dismissal, optional review, safe undo and existing confirmed removal/ownership behavior.
- [x] Automated regression coverage, formatting, strict analysis and Linux/Android debug builds.
- [ ] Owner acceptance on a physical phone, including theme settings, filters, tab scrolling and visit invitation gestures.

Local verification on 2026-11-25: 51 tests pass, including 320/390/1200 px layouts in both themes at 1.5 text scaling, labelled/touch-target accessibility checks, scope/chronology, long histories, filter reset and visit dismissal/undo. The strict analyzer accepts only the existing exact Material import diagnostic (21 files, including the new regression suite); no broad suppression or dependency change. Hosted CI is reported after push without waiting; physical acceptance remains open.

### Session 2 — Review wizard

- [x] Implement Global / Detalhes / Etiquetas steps, precise accessible star input, original category selectors and bounded tag selection; preserve draft, validation and atomic save/cancel semantics.
- [x] Add regression coverage and verify formatting, strict analysis and Linux/Android debug builds.
- [ ] Owner acceptance on a physical phone, including star precision/zero, caption wrapping, visit selection and keyboard behavior.

Local verification on 2026-11-25: all 61 tests pass. Coverage includes tenths/zero/unanswered ratings, keyboard and adjustable semantics, draft navigation/cancellation, fixed and selectable visit association, exact editing, atomic/repeated submission, searchable/removable/bounded tags, duplicate/count/unfinished-tag validation, capability visibility, and 320/390/1200 px layouts in both themes at 1.5 text scaling with simulated keyboard insets. Flutter-rendered captures of all three steps at 320/390 px in both themes were visually inspected, including partial stars, caption wrapping and custom-tag keyboard layout. The exact Material import baseline now includes the dedicated wizard regression suite (22 files); no broad suppression, dependency or schema changes. Physical phone acceptance remains open.

### Session 3 — Collection, rankings and profile

- [x] Implement collection/diary tabs, responsive progress/statistics and collectible catalogue views.
- [x] Implement compact ranking scope/metric/sort controls and rows with unchanged means, scales and tie ordering.
- [x] Refine the local profile and settings presentation using real derived statistics and navigation.
- [x] Add regression coverage and verify formatting, strict analysis and Linux/Android debug builds.
- [ ] Owner acceptance on a physical phone, including collection/diary scrolling, ranking controls, profile navigation and persisted theme.

Local verification on 2026-11-25: all 78 tests pass, including empty catalogues, unique discoveries versus repeat visits, optional/zero reviews, local calendar grouping, lazy 100-bathroom/101-visit lists, independent tab scroll restoration, profile navigation, all five ranking metrics and repeated-review means/counts. Layout and accessibility checks cover 320/390/1200 px, both themes and 1.0/1.5 text scaling. Flutter-rendered captures with readable text and bundled icons were inspected in both themes; the collection adapts from two phone columns to four desktop columns, or one column for narrow enlarged text. Strict analysis accepts only the exact Material import baseline (23 files); Linux and Android debug builds pass. No state, storage, dependency or schema changes. Hosted CI is reported after push without waiting. Physical phone acceptance remains open; Phase 2 has not started.

### Session 4A — Bathroom visual identity and experience refinement

- [x] Persist curated emoji/accent identities, deterministic defaults and meaningful sample identities; creation picker and randomize action.
- [x] Refine Explore identity, golden ratings, active sorting and conditional result counts; retain all discovery controls.
- [x] Refine details/category/tag presentation, experience-first history rows and reusable individual visit detail with ownership-aware review/removal actions.
- [x] Simplify direct review to atomic new-visit save; retain exact invitation/history/edit associations, safe undo, duplicate prevention and optional reviews.
- [x] Make system back traverse wizard steps and confirm discarding changed drafts.
- [x] Complete formatting, strict analysis, all 89 tests, Linux/Android debug builds and Flutter visual inspection.
- [ ] Owner acceptance of Session 4A on a physical phone.

Phone feedback on Sessions 1–3: the new information architecture and three-step wizard were well received. Session 4A responds to the need for more playful personality; this is not blanket acceptance of every earlier device checklist item.

Verified locally on 2026-11-25: all 89 tests pass, including v2 migration/relational/settings preservation, selected identity persistence/restoration, legacy tag text, explicit visit associations, atomic new review/cancellation/zero/duplicate handling, history navigation, ownership, editing, confirmed removal and undo. Formatting and strict analysis pass (only the exact documented Material-import baseline, now 26 files). Linux and Android debug builds pass. Layout checks cover 320/390/1200 px in both themes with enlarged text, alongside existing accessibility checks. Flutter-rendered Explore, details, experience and creation captures were inspected in light/dark themes with loaded text, icon and emoji fonts. Android system-back routing is covered through Flutter's route-pop handling; physical phone acceptance of Session 4A remains open. Hosted CI is reported after push without waiting. Session 4B is verified below; backend development has not started.

### Session 4B — Playful collection, diary, rankings and profile

- [x] More colourful collectible cards using shared bathroom identities and clearer collection progress.
- [x] Visually separated diary date groups with navigation to individual experience details.
- [x] Ranking podiums and stronger score hierarchy.
- [x] More expressive profile statistics and meaningful personal highlights; remove duplicated activity history from Profile.

Verified locally on 2026-11-25: all 92 tests pass, strict analysis accepts only the existing exact Material-import baseline, formatting and Linux/Android debug builds pass. Flutter-rendered collection, diary, rankings and profile were inspected in both themes at phone widths and enlarged text; sample three-place podiums were also inspected. No schema or storage changes. Physical phone acceptance remains open.

- [ ] Owner acceptance of Session 4B on a physical phone.

### Session 4C — Final UI polish

- [x] Replace category cards with horizontal discrete emoji scales; preserve unanswered/zero, exact selections and wizard drafts.
- [x] Centralize tag decoration and equivalent-label matching across chips/details/search; decorate fresh fictional seeds without schema changes.
- [x] Distinguish default Geral ranking from retained Por categoria tabs; preserve ranking calculations and navigation.
- [x] Integrate compact profile identity/statistics and adaptive highlights; keep favourites and the canonical header Settings gear.
- [x] Complete local verification and Flutter-rendered phone inspection.
- [ ] Owner acceptance of Session 4C on a physical phone.

Verified locally on 2026-11-25: formatting, strict analysis (unchanged exact Material-import baseline), all 100 tests and Linux/Android debug builds pass. Flutter-rendered 320/390dp screens were inspected in both themes at 1.0/1.5 text scaling, including emoji/slider alignment, tag glyphs, both ranking modes and responsive profile highlights. Regressions cover nullable/minimum and saved categories, tap/drag/keyboard/semantics, tag equivalence and validation, mode/category restoration, profile highlights/favourites and the header Settings route. The interactive HTML reference also passes JavaScript syntax and mode/unanswered/profile smoke checks. No dependencies, schema or ranking formulas changed. Physical phone acceptance remains pending owner confirmation.

Session 4B baseline `d46ad71` was independently verified with 92 tests and successful hosted CI. The owner tested the phone and approved these four refinements; this does not close outstanding physical acceptance checklists.

Shared identity components and the visit-detail route are reused. Do not start backend development as part of these sessions.

### Session 4D — Review interaction and data-model completion

- [x] Separate decorative fractional stars from an explicit accessible 0–5 slider in tenths; preserve nullable/zero/edit semantics and discrete category scales.
- [x] Persist structured emoji/label tags, canonical equivalence and capability-gated creation with emoji keyboard, suggestions and preview.
- [x] Add optional 500-character comments to the third wizard step, drafts, editing, SQLite and experience/community presentation.
- [x] Preserve existing data through a transactional v4 migration and seed deterministic fictional structured tags/comments on fresh installs.
- [x] Update model/storage/design/reference documentation and verify automated regressions, formatting, strict analysis, Linux/Android builds and rendered phone layouts in both themes with enlarged text.
- [ ] Owner acceptance of Session 4D on a physical phone.

Local verification: 105 tests pass, including structured sequences, equivalence, custom creation, comments/drafts/cancellation, v3 upgrades and persistence, alongside all existing regressions. Both debug builds and the exact strict-analysis gate pass. Flutter-rendered 320/390dp light/dark layouts with enlarged text were inspected. This was the pre-backend baseline; classification remains exploratory and public catalogue/contribution direction is preserved. [Hosted Android CI for `e21ab7a`](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45676274279) completed successfully. Physical-phone acceptance remains pending.

## Phase 2 — Community functionality (proposed implementation sequence)

### Phase 2.0 — Backend architecture and portability evaluation

- [x] Inspect the current Provider/SQLite boundaries and compare Supabase/PostgreSQL, PocketBase and Appwrite using current official documentation.
- [x] Document proposed ownership, offline synchronization, idempotency, guest association, fictional-data exclusion, privacy and authorization boundaries in [architecture](docs/backend/architecture.md).
- [x] Assess Free-plan constraints, self-hosting, account/object portability, costs and a reproducible exit/acceptance procedure in [portability](docs/backend/portability.md); record the conditional recommendation in [ADR 0001](docs/backend/decision-0001.md).
- [x] Add and realize an optional backend Nix shell using the existing lock; inspect existing rootless Podman without changing system configuration.
- [x] Verify a network-disabled, rootless Supabase PostgreSQL component smoke test with fictional insert/export/restore and cleanup; verify configuration checks.
- [x] Owner acceptance of Supabase/PostgreSQL as the bounded Phase 2.1A candidate and fictional PoC assumptions.
- [ ] Owner decisions on remaining production product rules and production hosting after the exit gate.

At completion of Phase 2.0, Supabase managed Free was recommended conditionally and no cloud project or real managed restore had been implemented. Phase 2.1C below now verifies the bounded managed exit; production acceptance, remote synchronization and the shared catalogue remain open. Session 4D physical-phone acceptance remains open independently.

Verified locally on 2026-11-25: formatting, strict analysis (existing exact Material-import baseline), all 105 tests, Linux/Android debug builds, actionlint, Bash syntax/ShellCheck, local documentation links and `nix flake check --no-build --no-write-lock-file` pass. The optional shell realizes CLI 2.111.0, PostgreSQL client 17.12 and Podman/Compose from the existing lock. The first component restore encountered the already-existing `public` schema; the disposable script now explicitly cleans/recreates only its fictional dump scope and the rerun passes. No network/ports or test containers remain. This verifies basic SQL dump/restore within one disposable database container, not Auth/API, an independent full-stack restore or a managed exit. Full acceptance remains in Phase 2.1. No Flutter code, dependencies or SQLite schema changed.

### Phase 2.1A — Local Supabase proof of concept, schema and authorization (completed)

- [x] Accept the bounded candidate and explicitly provisional public/private/Auth assumptions, retaining the conditional production exit gate.
- [x] Pin a minimal rootless PostgreSQL/Auth/PostgREST Compose stack with exclusive loopback bindings, private disposable credentials, dedicated resources and documented lifecycle commands.
- [x] Version SQL migrations, UUID relationships, rating/content validation, immutable associations, grants, RLS and separate opt-in fictional fixtures.
- [x] Verify real Auth signup/password login/refresh/logout/expiry and A/B API/SQL authorization, public projection/join privacy, self-approval and privilege-escalation rejection.
- [x] Verify clean initialization, transactional rollback, ordinary stop/start persistence, resource measurements and all existing Flutter regressions/builds.
- [x] Update backend runbooks, provisional-decision boundaries and changelog.

Verified on 2026-11-25: **232 assertions on a clean fictional stack**; PostgreSQL 17.6, Auth v2.198.0 and PostgREST v14.18 pinned by digest. All 105 Flutter tests, formatting, strict analysis, Linux/Android debug builds, Python lint/format, Compose parsing, effective loopback/rootless checks, actionlint, Nix flake evaluation and documentation links pass. Stop/start preserved fixture UUIDs/counts, migration history and credentials. Approximate idle usage: 90–140 MB RAM, 0.35% of one CPU core over a 10-second sample, 1.36 GB uncompressed images and 42 MiB database files. See [commands, evidence, limitations and failed-check corrections](docs/backend/local-poc.md). Logout revokes refresh/Auth sessions; issued API JWTs remain usable for their 60-second lifetime plus up to 30 seconds of PostgREST clock skew. Server codepoint limits are deliberately stricter than Flutter grapheme limits, with explicit Unicode tests. No system configuration change or cloud project; Flutter/local persistence remain unchanged. Hosted CI is reported after push without waiting.

### Phase 2.1B — Independent local full-stack portability rehearsal (completed)

- [x] Export database/Auth/configuration and any enabled object fixtures; restore into an independent self-hosted target without shared volumes/source access.
- [x] Verify unchanged-password login, identity/content/constraint/RLS preservation, refreshed sessions and the repeated authorization matrix.
- [x] Record exact versions, exports/checksums, timing, resource needs and failed checks. This local rehearsal alone cannot prove the managed exit.

Verified locally on 2026-11-26: independent rootless installations, logical schema/data/Auth identity export with private checksums, exact row/inventory comparisons and foreign-key revalidation, original-password A/B login with unchanged UUIDs, new refresh sessions, rejection of still-unexpired source JWTs and source refresh sessions, independent destination restart, and 226 authorization assertions with signup disabled. Source stopped and preserved. See [commands, measurements, corrections and limits](docs/backend/local-migration.md). Object storage is unselected/untested; managed exit, ARM and production readiness remain unverified. No Flutter backend integration or cloud resources.

### Phase 2.1C — Actual managed-Free exit rehearsal (exit verified; production decisions open)

- [x] Owner created and authorized the dedicated fictional-data managed Free test project.
- [x] Complete verified-TLS/no-email preflight, real managed-Free-to-independent-self-hosted export/restore, original-password login and authorization checks. See [scope, measurements and compatibility corrections](docs/backend/cloud-migration.md). The bounded managed exit rehearsal passed; production acceptance remains open.

Verified on 2026-11-26: explicit Auth settings booleans confirm signup enabled and email autoconfirm enabled; no confirmation emails or admin bypass. Managed matrix **231 assertions** (long-lived managed expiry wait explicitly omitted); third independent rootless target **226 assertions**, including real expiry. Exact complete application/Auth identity rows and hashes, application RLS/definitions/grants, revalidated foreign keys, original-password/UUID login, new refresh, rejection of unexpired source JWTs/source refresh, and independent restart passed. Managed compatibility edits and target default-grant reconciliation are recorded; original exports and private checksummed evidence retained. Export **19.114 s**, atomic restore **0.187 s**, about **93 MB** immediate destination memory. All three local installations are stopped/preserved; the managed project is retained. Final verification: Ruff lint/format, five Python tests, Dart formatting/strict analysis, all 105 Flutter tests and Linux/Android debug builds pass. After a PC crash, 31 evidence-file checksums and original-password/UUID login passed again. No Flutter integration, paid resource, new dependency or system configuration change.

- [x] Extract the private managed export/restore scripts into version-controlled independent commands with 25 passing offline Python regressions (including an isolated synthetic PostgreSQL ACL/rollback check), Ruff checks and documented usage. All 105 Flutter tests and Linux/Android debug builds pass; current strict analysis reports 26 existing SDK Material import deprecations in unchanged code. Historical end-to-end evidence remains at `9b634c9`; the refactored tooling has not been rerun against databases. See [tooling](docs/backend/cloud-transfer-tooling.md).

- [ ] Resolve production email delivery, target architecture/resources, backup/restore ownership, recovery objectives and running-cost limits without requiring paid subscriptions, domains or new hardware.
- [ ] Obtain production hosting acceptance only after successful exit evidence and remaining product decisions.

### Phase 2.2A — Local repository, incremental persistence and provenance

- [x] Add one BathroomRepository at the state action boundary; retain Provider/ChangeNotifier/SQLite and existing UX.
- [x] Replace ordinary snapshots with targeted atomic transactions; commit before observable mutation success and retain exact failed input for explicit retry.
- [x] Upgrade distributed v4 non-destructively to v5; persist conservative provenance and exclude demo/unclassified legacy from the necessary future-upload gate.
- [x] Verify migration/initialization, incremental footprints, read/notification purity, atomicity/rollback/retry, restart and provenance with all existing regressions and requested builds.

Verified locally on 2026-11-26: **114 Flutter tests pass** (all 105 existing regressions plus nine targeted repository/migration tests); formatting, strict analysis with the unchanged exact Material-import allowlist, Linux debug and Android debug APK builds pass. All **25 backend regressions pass** in the locked backend shell, including a temporary Unix-socket-only PostgreSQL test; no preserved installation or managed project was touched. Read/notification purity and per-action write footprints are checked with SQLite change counts/audit triggers; injected failures prove rollback, unchanged committed state, completion ordering and retry without duplicates. Distributed v4 fixtures retain exact original column values and gain conservative provenance. Earlier validation attempts exposed cache sandbox access, three brace lints and a misplaced await in discard handling; these were corrected before the final passing runs. See [storage semantics and limits](docs/storage.md). Pending failed input remains memory-only until retry; no durable outbox, account or synchronization work is complete. Hosted CI is reported after push without waiting.

### Phase 2.2B — Account namespaces, durable outbox and client synchronization foundation

- [x] Add non-destructive account namespaces and durable outbox transactions with stable operation identity; retain guest use and exclude fictional/unknown data.
- [x] Introduce only needed data-source/session/coordinator boundaries and client revision/tombstone/checkpoint storage; verify account isolation, offline/restart/retry behavior.

Verified locally on 2026-11-26: **142 Flutter tests pass**, retaining all 114 regressions plus 28 synchronization tests; formatting, strict analysis with the unchanged exact Material-import baseline, Linux debug and Android debug APK builds pass. All **25 offline backend regressions pass** in the locked backend shell, including the fresh Unix-socket-only PostgreSQL test. No managed project or preserved installation was accessed. v5 upgrades retain exact original rows/provenance/settings in guest; separate scope-bound files isolate accounts/environments/public cache. Tests cover atomic outbox/compound writes and rollback, pending restart, lost/interrupted acknowledgment and stable-ID deduplication, bounded dependency ordering/backoff, authentication expiry/switch/logout, conflict/draft/deletion persistence, stale resurrection protection and atomic pull/checkpoints. Production bootstrap remains guest-only with no queueing or networking; explicit test contexts exercise account mutations. Pre-commit failures/unsaved UI drafts remain memory-only; committed operations, retries, conflicts and checkpoints are durable. Initial checks exposed missing test timestamps, expected v5 version assertions and brace lints; corrected before the final passing runs. See [implementation, error semantics and server requirements](docs/backend/client-synchronization.md). Hosted CI is reported after push without waiting.

### Phase 2.2C — Server synchronization protocol and end-to-end verification

- [x] Implement server idempotency, revision/conflict/deletion semantics and scoped pull checkpoints under server-enforced ownership/privacy.
- [x] Verify end-to-end synchronization, late commits during pagination, crash/retry/idempotency, conflicts and fictional/unknown-data exclusion before account/publication rollout.

Implemented after `e0d620a` in ordered migration 0002: authenticated commands bind durable account/operation receipts to immutable requests, validate causal predecessors, use shared transactional compound revisions/CAS, retain terminal tombstones, and preserve the existing grants/RLS/moderation/public projection restrictions. A transaction-held writer lock orders change allocation through commit; opaque, independently scoped bounded feeds safely replay the retained log on cursor expiry. Never-public identifiers remain private on deletion. The test-only HTTP adapter validates server-derived subject binding and complete compound acknowledgments. Guest bootstrap, UI, Portuguese text, rating descriptions, rankings and SQLite v6 domain storage remain unchanged; no Phase 2.3 work or production account/upload path is enabled.

Verified locally on 2026-11-26: **144 ordinary Flutter tests pass** (all 142 retained regressions plus two acknowledgment/visibility tests), with the explicit real-suite placeholder skipped in ordinary runs; **all seven real Flutter integration tests pass separately**. Formatting, the unchanged exact analyzer baseline, Linux debug and Android debug APK builds pass. All **25 offline backend regressions**, including the fresh Unix-socket-only PostgreSQL test, and Ruff lint/format pass. The final fresh installation passes **232 authorization/authentication assertions** including real JWT expiry and **154 server synchronization assertions** (counts include bounded pagination over the fixture log). Real checks cover separate Dart processes, committed pending work, server commit without local acknowledgment, concurrent duplicate requests, changed-ID rejection, predecessor validation, atomic compound rollback/revisions, two-device conflicts, stale delete/edit/resurrection, expired/mismatched authentication, switch invalidation, private/public scopes, reverse candidate commit ordering and actual writer-lock blocking, cache/checkpoint rollback and provenance exclusions. See [actual contracts, error classifications, evidence and limits](docs/backend/server-synchronization.md).

Only the new independent rootless `bath-royale-poc-sync` installation on loopback ports 55461/55462 was used; it is stopped with private credentials, volumes and network retained. No managed project or preserved migration installation was accessed. Initial checks exposed a pre-existing fixture favourite conflict, an unnecessary import, a Nix-shell PYTHONPATH invocation issue and a never-public deletion-marker leak; fixtures/invocation/code were corrected before the final successful runs. The transport also rejects an intentionally mismatched subject/token response. PostgreSQL codepoint/emoji constraints remain stricter than Flutter grapheme validation: the precise Unicode compatibility gate is documented without changing user-facing semantics. Private-history consent, production Auth/account association, public metadata/moderation, log/tombstone retention/compaction, erasure, conflict resolution and exporting the new protocol metadata remain deferred. Hosted CI is reported after push without waiting.

### Phase 2.3A — Offline account integration foundation

- [x] Extend the existing session boundary with observable unauthenticated/authenticated/expired/invalidated states and generation-safe renewal, switching and logout through injected fake authentication.
- [x] Prepare isolated account AppState/Provider lifecycles on the existing namespace files, with empty account initialization, retained drafts/failed commits and durable original-account pending operations.
- [x] Keep identity separate from association/upload/publication/synchronization authorization; leave normal bootstrap guest-only and all production account/sync paths disabled.
- [x] Verify all ordinary regressions, offline backend tests, exact analyzer baseline, formatting and Linux/Android debug builds; document production boundaries.

See [offline account integration](docs/backend/offline-accounts.md) for implementation, test-only lifecycle semantics, durability and the remaining production gates. No production authentication method, SDK, credential persistence, account-selection or device-data retention policy is selected in 2.3A.

Verified locally on 2026-11-26: **170 ordinary Flutter tests pass** (all 144 existing regressions retained plus 26 new), with the ordinary real-suite placeholder intentionally skipped. Formatting, strict analysis with the **unchanged exact Material-import baseline**, Linux debug and Android debug APK builds pass. All **25 offline backend regressions pass**, including their isolated temporary Unix-socket-only PostgreSQL fixture. Documentation links and Git whitespace checks pass.

Coverage includes guest startup without Auth/networking, empty account initialization, subject/environment isolation, renewal/expiry/invalidation/logout/switching, delayed renewal/open/submit/pull invalidation, identity without transfer consent, preserved guest/pending data, safe Provider route/listener replacement, actual review/bathroom drafts across session loss, and failed pre-commit rollback/retry. Final review also fixed and verified cancellation when reselecting the current guest while an account open is pending. Initial test fixtures omitted required review answers and the first analyzer run exposed test-only protected-member/unused-import/brace diagnostics; these were corrected before the final passing runs. The initial sandboxed Flutter invocation could not write its existing telemetry file; authorized toolchain/cache access allowed all final checks.

No server schema, wire protocol, HTTP transport or remote method contract changed, so the real integration suite was not rerun; its seven passing tests at baseline `321d1ea` remain historical evidence. No managed project, preserved backend installation, dependency or global NixOS configuration was accessed/changed. Session/draft/pre-commit input remains memory-only, committed original-account operations remain durable, and no production retention or consent policy is inferred. **Stop at 2.3A; 2.3B/2.3C are not started.** Hosted CI is reported after push without waiting.

### Phase 2.3B — Production authentication and device lifecycle (not started)

- [ ] Approve production authentication method and email delivery/confirmation/recovery; implement and verify a real session adapter.
- [ ] Approve and verify secure credential persistence on Android/Linux, account selection/logout, offline account access and device-data retention/removal, including unsaved drafts and failed local commits.
- [ ] Define account/public-cache view composition and lifecycle before enabling production account views; retain fully functional guest mode.

### Phase 2.3C — Consent, explicit association and private synchronization (not started)

- [ ] Approve separate private-history/favourites synchronization consent and explicit guest-data association; preview only eligible genuine data and verify duplicate association/isolation/atomic retry.
- [ ] Resolve Unicode grapheme validation compatibility and recoverable validation/conflict UX without changing local draft semantics silently.
- [ ] Verify portability of the new synchronization metadata (or a safe new epoch); earlier managed migration evidence does not cover it.
- [ ] Enable opt-in private synchronization only after these gates and server-enforced ownership verification. Public profile creation, attribution and publication policies remain explicit gates for Phase 2.4/2.5.

### Phase 2.4 — Shared catalogue and reviews

- [ ] Implement approved public catalogue/review projections separately from private visits; preserve bathroom/visit/review distinctions and existing score scales.
- [ ] Add pending contribution submission, revision/conflict handling, structured tag snapshots and review comments with server-side validation.
- [ ] Keep geography/institution, contributor origin and verification independent; leave bathroom classification exploratory and exclude private bathrooms.

### Phase 2.5 — Moderation and community readiness

- [ ] Approve/implement moderation, reporting, author edits/takedowns, attribution and account/data deletion rules before public content launches.
- [ ] Preserve original contributor credit through administrative approval. Defer recognition/reward systems to a separately approved milestone; reward approval rather than submission.
- [ ] Complete privacy/security review, recovery/cutover rehearsal, non-destructive migration tests and relevant physical-device acceptance. Recheck commercial quotas and exit feasibility before real users.

## Phase 3 — Location and discovery

- [ ] Add an interactive map and geolocation.
- [ ] Support nearby bathrooms and a hierarchy of buildings, campuses, cities and countries.
- [ ] Add bathroom photos with appropriate privacy protections.

## Phase 4 — Gamification and social features

- [ ] Add achievements, XP and levels.
- [ ] Show exploration statistics and leaderboards.
- [ ] Introduce friends and challenges.

## Phase 5 — Release preparation

- [ ] Improve responsive layouts.
- [ ] Prepare Android builds and web deployment.
- [ ] Develop branding.
- [ ] Complete a privacy and security review.
- [ ] Prepare and launch a public beta.

### Verified data-model milestone

Bathroom entities, visits, individual author-owned reviews and per-user favourites are separated in memory. Latest visits are derived from visit records. Multiple reviews, latest personal ratings and community means are covered by unit and widget regression tests. Cards and filters retain their existing personal-rating behavior. See [data-model semantics](docs/data-model.md). Details and review forms are now implemented; the remaining Phase 1 milestones remain open.

### Android build verification

The Nix Android environment and Flutter 3.50.1 template migration are verified with a debug APK build (Gradle 9.5.0, AGP 9.3.1, KGP 2.4.20, Java 17). Application ID is unchanged. Physical Android execution is confirmed by the owner and the updated app successfully connected through flutter run. Android release signing/builds and web deployment remain open; this does not complete Phase 5 release preparation.


### Bathroom creation and Explore milestone

Verified in memory: validated creation with normalized duplicate-name prevention, name search, four deterministic sort orders, explicit personal/community labels, filter reset and empty states. Twenty unit/widget tests pass, including 390 px and 1200 px creation flows. Formatting, Linux debug/release and Android debug APK builds pass. Analysis retains only the documented Material import deprecations. This historical milestone preceded local persistence; broader test coverage and release preparation remain open.

### Mobile UI refinement

Review ratings and tags, explicit visit feedback and undo, and compact Explore controls are implemented and covered by regression tests. Linux and Android debug builds are verified. Broader responsive design and release preparation remain open.

### Visit and review integration

Every review belongs to one visit; visits may stand alone. The in-memory prototype supports repeat visits, a visit-based collection, optional reviews, history, conditional undo and confirmed removal. Twenty-one tests and Linux/Android debug builds pass; analysis reports the known Material import deprecations. This milestone preceded the local persistence milestone below.

### Local persistence

SQLite stores all entities, independent favourites and theme settings. UUIDs support local identity generation; latest personal reviews follow visit chronology and rapid registration reuses the same visit. Versioned migrations, atomic snapshots, first-run seeding and non-destructive storage error handling are implemented and verified with 29 tests, formatting and Linux/Android debug builds. Analysis retains only the Material import deprecations. See [storage architecture](docs/storage.md).

### Rankings and collection

Local rankings show arithmetic means of all reviews in the chosen personal/community scope, category scales and review counts, with best/worst ordering and deterministic ties. Collection discovery follows visits, with progress against the current local catalogue, dynamic statistics and chronological history. Custom tag entry is revealed on request. Persistence restart was confirmed by the owner on a physical Android device.

### Future catalogue and contribution policies (direction only)

- All published bathrooms are publicly discoverable; private bathrooms are removed from the vision. Personal history may remain private independently.
- Validate/moderate user proposals before publication. Reward approved contributions, preserving original attribution through administrator validation/promotion. XP, achievements and recognition are possibilities; exact mechanics remain open.
- Explore inside/outside University of Aveiro presentation without deciding names, rules or geographic hierarchy. Model membership, origin/attribution and verification as distinct concepts, allowing a user-contributed university bathroom. Consider other institutions, campuses and cities.
- No visibility categories, moderation, authentication, permissions, contribution rewards, XP, achievements or power-ups in Session 4A.

Rankings/collection verification: all 33 tests, formatting and Linux/Android debug builds pass. Analysis reports only 18 Material import deprecation notices. No schema changes were needed.

### Final Phase 1 acceptance

The local prototype acceptance criteria are satisfied: all 36 automated tests, formatting and Linux/Android debug builds pass. Analysis reports only 20 known Material import deprecations. Hidden tag validation, tab-specific creation, ranking explanations and the local profile are stabilized. See [audit evidence and deferred debt](docs/phase-1-audit.md). This completion does not complete release preparation or authorize community/backend implementation.
