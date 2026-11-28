# Roadmap

The phases describe intended sequencing, not a fixed specification. Unconfirmed details are proposals and may change with product decisions and implementation findings. Check items only when implemented and verified.

## Current priority — A7.3.1 automatic backup activation

The owner has reprioritized delivery to a small group of friends. Phase A1 below supersedes the optional writable guest/embedded Profile authentication decisions in the historical Phase 2.3B entries. Existing completed foundations remain available; later roadmap items do not authorize implementation.

**A5 initial alpha is complete:** [alpha 1039](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1039) is published and independently verified. The owner confirmed physical acceptance on the existing phone; second physical device testing remains pending. Dedicated project support and appropriate verified-email authentication/recovery remain mandatory before public launch.

### A6.1 — Performance and stability investigation

Owner-authorized priority after reports of online sluggishness following refresh and navigation. Diagnose and fix these problems before new features. **Performance physically accepted by the owner for `97e14ae`; historical ANR stack attribution remains unproven.**

- [x] Inspect the actual SM-A166B installation: signed release 1038, retained identity/data, startup, app-scoped logcat, historical input ANR, CPU, memory and compositor diagnostics. Measure Flutter frames and derived-data calculations in a separate release-mode fictional-data application on the same phone; never use debug timings as release evidence.
- [x] Remove measured repeated catalogue decoding, nested entity/activity scans and ranking identity queries; preserve score/chronology/privacy semantics without a long-lived cache or schema change. Reproduce and fix premature completion of overlapping catalogue refreshes.
- [x] Verify targeted regressions, 248 Flutter tests, strict analysis, real disposable community/protocol/offline/restoration suites and Android/Linux releases. Prepare and install signed code-1040 RC in place with the original certificate and first-install timestamp; keep publication disabled.
- [x] Owner physically tested and approved the performance improvements in `97e14ae`, reporting that the application feels substantially better. Second physical device testing and historical ANR stack attribution remain outstanding.

See [measurements, limitations, reproducible probe and exact acceptance steps](docs/performance-stability.md). Local calculation improvements do not establish that every reported bug, startup delay or historical ANR is resolved. The historical investigation did not authorize publication; the subsequent explicit owner approval and verified v0.1.1 publication are recorded below. No managed database reset/fixture operation is authorized.

### A6.2 — Catalogue reconciliation and v0.1.1

- [x] Diagnose retained catalogue membership overriding public deletion/visibility and insert-only shared metadata projection.
- [x] Reconcile public availability independently from historical account parents; retain visits, reviews, favourites, pending operations and links across deletion, hide/restore, offline restart and interrupted refresh. Update cached names and visual identities.
- [x] Verify 258 Flutter regressions, strict analysis, tooling/backend tests and Android/Linux release builds. Update the existing SM-A166B in place to signed v0.1.1 code 1045; confirm 36 → 30 catalogue entries, 7 → 1 DETI search results and retained account/identity through offline cold restart.
- [x] Owner physically tested and approved all v0.1.1 performance/catalogue fixes and explicitly authorized publication; no managed data changes or reset.
- [x] Publish signed code-1046 v0.1.1 as Latest through the controlled workflow; independently verify actual APK/certificate/version/checksum and anonymous downloads, preserve alpha-1039/history, update README and restore `ALPHA_RELEASE_APPROVED=false`. [Release evidence](docs/releases/v0.1.1.md). A6 is closed.

See [reconciliation protocol and candidate evidence](docs/catalogue-reconciliation.md).

### A7 — Independent owner manager (approved architecture)

This supersedes all previous A7 proposals. Two adjacent primary clones: `~/Documents/bath_royale` and `~/Documents/bath_royale_manager`. Public application owns Flutter, schema/migrations, official catalogue/content, app-specific tested tools and public build/release CI. The private manager owns Python `bRoyale` CLI/future Textual TUI, orchestration, encrypted SOPS+age credentials, backup/release management and the owner handbook. It has independent versions/tests/CI and reuses app interfaces rather than duplicating domain or security logic.

- **A7.1 — Foundation/organization (complete):** close A6; private repository; metadata-only resource inventory; portable configuration and canonical private resource paths; disposable-secret SOPS/age tests; `--help`, `version`, `status`, `doctor`, `paths`, `setup`; pinned Nix package/app/shell; owner handbook and explicit migration/recovery approval gate. No managed mutation, existing credential relocation/retirement or production secret commit.
- **A7.2 — Database administration (complete; operational handover in the owner handbook):** application-owned versioned JSON protocol, existing importer/RPC/sync reuse, read-only aggregates/inspection, CSV import/corrections, community appearance/visibility and dependency-safe removal, creator permissions, tag observation and anonymous feedback/moderation. Explicit targets and transaction-bound plans; no managed acceptance mutations. See [protocol and verification](docs/backend/administration.md). [Backend CI 46103194094](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/46103194094) passes for `3cb899d`, including 48 backend tests and isolated/concurrent mutation verification. Broader tag edits, sensitive account actions and permanent official retirement remain constrained by approved procedures/owner decisions; no new migration/public RPC/APK.
- **A7.3 — Backups/recovery (implementation complete; owner activation pending):** application-owned supervised transaction/advisory locks around the native exporter, sealed creation identities, real isolated lock-loss tests and complete disposable Auth backup fixture. The private manager owns encrypted atomic sets, conservative inventory/automatic mutation prerequisites, mandatory fresh restoration, copy/readback previews, plan-only retention and disabled user scheduling. Exact managed backup/cloud/scheduling acceptance requires owner approval; no credential retirement, APK release or A7.4 work. Verification is recorded in the private owner handbook.
- **A7.3.1 — Automatic backup activation:** correct the application-owned client/pooler TLS observation while preserving all native export/restore guarantees. The independent manager owns actual managed backup/copy acceptance, safe reviewed/automatic routine retention, Legion-only Home Manager scheduling and renewed granular verification. Independent private-key rehearsal remains owner-operated; no A7.4 or release publication is included.
- **A7.4 — Releases/CI:** one app version authority, semantic versions and monotonic Android codes, development/RC builds, explicit signed-publication approval, gate cleanup, APK/checksum/fixture verification, notes/downloads, CI diagnostics, secret management without values, previous-release preservation/rollback. Consolidate duplicated strings in pubspec, build/installer/workflow and feedback defaults through an app-side interface.
- **A7.5 — Textual TUI:** keyboard-driven overview/catalogue/users/tags/feedback/backups/releases/GitHub/environments/configuration over existing services, visible environment and explicit dangerous-action confirmations. No separate GUI or administration server.
- **A7.6 — Operational overview:** database/application aggregates, backup health, Supabase usage/quotas, release/CI/feedback/service diagnostics without unnecessary personal data or intrusive analytics.

Sensitive migration needs separate owner approval of exact sources/destinations, consumer changes, verification, rollback and cloud coverage. Every machine has its own age identity; an independent offline recovery recipient is required. Removed recipients retain historical access; compromised devices require credential/session rotation as appropriate. External CLI logins stay independent. Do not modify global NixOS/Home Manager configuration.

A7.1 foundation is verified in the independent private manager: Python CLI/shared services, 26 passing tests, pinned Nix package/app/shell and successful independent CI. Its sensitive migration/recovery plan is prepared for separate owner approval; existing credentials/resources remain in place.

The private manager is the canonical location for project-specific operational inventory and its single handbook; public documentation contains only repository responsibilities and roadmap. Later A7 phases are not authorized by A7.1.

### Phase A1 — Simplified authentication

- [x] Replace writable guest startup with an account gate and dedicated sign-in/registration screens; move Profile account management to that flow. Require an authenticated local identity for bathrooms, visits, reviews and favourites.
- [x] Preserve the original guest files without opening, deleting, uploading or associating them; retain account SQLite files, secure sessions, offline local access and logout/relogin isolation. No schema reset.
- [x] Disable mandatory email confirmation exclusively in the isolated local alpha Auth instance. Keep the ordinary production configuration and confirmation/recovery flow available; clearly disclose unavailable local-alpha password recovery.
- [x] Validate Portuguese forms, password visibility, busy states and visible incorrect-credential feedback, including small screens/large text/keyboard. Verify registration without confirmation, restoration, offline access and account isolation.
- [x] Prepare and verify the private signed Android APK with the existing package/certificate and previously installed code 1023; verify Android and Linux releases.
- [x] Install the private account preview in place on the connected phone, preserving package/signing identity and code 1023; subsequent A1.1/A2 update evidence is recorded below. No uninstall or data clear.
- [ ] Owner physical acceptance: Android Keystore restart, actual offline/reconnection behavior, logout/relogin, A/B isolation, keyboard and retained data.

Unauthenticated shared-catalogue browsing is an approved requirement **when that catalogue exists**. There is no shared catalogue in A1. No-config public builds display an unavailable-account explanation; they do not expose the former guest writer. Existing guest data remains archived on-device and is not shown or imported into new accounts. A1 does not create public profiles or upload domain data. See [the A1 decisions, verification and limitations](docs/backend/authentication-roadmap.md).

### A1.1 — Authentication UX corrections

- [x] Add welcome on signed-out startup/logout, separate sign-in/registration routes, visible/system back, field validation, upfront registration requirements and email/password autofill/focus actions.
- [x] Retain authenticated restoration, incorrect-credentials feedback, local-validation drafts and secure request handling; add focused regressions and a documented update-only private installer.
- [x] Owner acceptance of A1.1 Android authentication UX (confirmed before authorizing A2).

### Phase A2 — Private account data synchronization

- [x] Connect the existing transactional outbox, authenticated HTTP adapter, server receipt/CAS/pull protocol and account-scoped stores to the configured app. Preserve offline actions, secure persistent Auth, local records and account isolation.
- [x] Explain private upload and obtain persistent explicit consent per account/device before transferring account-owned bathrooms, visits, reviews and favourites. Never import/upload archived guests or fictional/unclassified examples; keep fresh accounts empty.
- [x] Separate private ownership from optional public profiles. Enforce private bathroom/history/favourite/unpublished-review isolation, including anonymous/other-account access and denial through the existing publication/moderator paths. No A3 functionality.
- [x] Add bounded foreground synchronization, pending/error status, durable transport retries, duplicate/lost-ack handling, renewal after rejected sessions, safe account transitions, conflict preservation and explicit resend/correction/archive/full-replay recovery. Stop idle polling and paused-run continuations.
- [x] Match server text validation to the locked client grapheme semantics without truncating content; verify 1,093 Unicode vectors. Preserve original rejected payloads. Verify complete sync metadata/sequence export and isolated restoration, receipt replay, scoped cursor continuation and restored-xid collision handling.
- [x] Verify two independent stores using a profile-free account, offline reconnection/convergence, concurrent edits/deletions, A/B isolation, v6 → v7 preservation and restarts. Run regression/integration checks and Android/Linux release builds.
- [x] Install private `0.1.0-alpha-a2.1023` / code 1023 in place on SM A166B with the original certificate. `adb install -r` succeeds; first-install timestamp remains `2026-11-26 22:40:55`, and USB forwarding/launch are restored. No uninstall or data clear.
- [ ] Owner physical A2 acceptance: retained records, consent/decline, real offline/restart/reconnection, second-device convergence, conflict recovery, A/B isolation and Keystore behavior.

See [A2 architecture and recovery semantics](docs/backend/private-account-synchronization.md) and [USB/loopback device acceptance](docs/android-auth-device-testing.md#a2-physical-acceptance). A1.1 follow-up removes logout from password change while retaining account-management logout. No managed-project deployment, configured-APK publication, guest association, public identity or A3 catalogue/publication work is included. Remote registration restrictions, retention/erasure, real-user migrations and hosting remain separate release decisions.

Verified on 2026-11-27: **212 Flutter tests pass** with the actual local gateway TLS/route check enabled (two opt-in real-suite placeholders skipped); the separate real HTTPS SDK/device-scope suite passes with synchronization into a second store. The complete disposable backend runner passes **227 authorization/authentication assertions**, **1,093 Unicode parity cases**, **628 server protocol assertions**, profile-free privacy/publication-denial checks and **8 real Flutter synchronization tests**, then verifies logical export/restoration and stops its dedicated containers. **26 offline backend tests** and **9 preview/device-tool tests** pass. Dart formatting and strict analysis pass with the narrowly reviewed Material-import baseline for the A2 view; backend Ruff lint/format passes. Unconfigured Android and Linux release builds pass; the Android universal AOT package and original preview certificate are verified. Private Android release also passes universal AOT/certificate checks and is installed in place as above (59,411,322 bytes). Actionlint passes; the installer enforces the dependency lock. Physical A2 acceptance remains open.

Earlier iteration failures (schema-fixture version assertions, Unicode empty/grant handling, a historical profile-join expectation, the Dart-only process fixture and chunked requests rejected by the narrow USB gateway) were corrected and their targeted/final checks rerun. No failed attempt is counted as a passing result. The v7 account migration and remote projection are non-destructive; no local database/schema reset was used.

### Phase A3 — Shared catalogue and community experience

- [x] Owner-approved A3 scope and automatic account synchronization after clear acceptance; approval is the implementation request of 2026-11-27. No managed deployment, configured-APK publication, paid infrastructure, A4 or A5.
- [x] Add the common catalogue, stable identities, normalized duplicate prevention, anonymous public projections and explicit private-to-shared association without publishing/reparenting historical data. Add published-only review projections, independent public identities/usernames, owner edit/withdrawal, reporting and protected administrative moderation.
- [x] Verify direct API authorization, A/B isolation, duplicates, publication/withdrawal/moderation, historical-feed privacy, populated community/private export/restoration and existing server/client protocol regressions in disposable infrastructure.
- [x] Complete automatic accepted account storage, persistent anonymous catalogue caching, personal/shared composition, clear private/shared labels and Explore/details/rankings/publication/moderation integration. Verify 224 Flutter regressions, real community/API/protocol/portability suites, actual local HTTPS Auth, strict analysis and Android/Linux releases. Install private `0.1.0-alpha-a3.1023` in place on SM A166B with the original certificate, app ID and first-install timestamp; no reset, association or publication on the owner’s behalf.
- [x] Owner accepted A3 functional tests before authorizing A3.1. This does not imply new A4 design or production/privacy approval. Platform-specific checks not covered by that acceptance remain separate.

See [A3 architecture, reproducible milestones and verification](docs/backend/community-alpha.md). The A3 decision supersedes A2's normal optional enable/pause modes and the historical per-item manual catalogue-approval proposal. Guest archives/examples remain excluded; remote alpha distribution/registration policy and A4/A5 remain deferred.

### A3.1 — Community simplification and development fixtures

- [x] Deliver shared-only normal workflows, anonymous automatic public new reviews and protected bathroom-creation entitlement, preserving historical privacy and original references.
- [x] Simplify signed-out navigation, account/Settings identification, storage acceptance, automatic refresh and recovery; hide administration from ordinary users.
- [x] Verify idempotent isolated fictional accounts/catalogue/activity, private credential reference, and a separately compiled local-development selector absent from distributable builds. Never overwrite owner accounts.
- [x] Consolidate previous/current owner feedback in [the A4 backlog](docs/bath-royale-design/ui-design.md#a31-functional-simplification-and-a4-backlog). Comprehensive visual redesign remains deferred.
- [x] Complete regression/API/fixture/isolation/build verification and update the connected phone without clearing data to the explicitly authorized development build. See [resumable A3.1 evidence](docs/backend/community-simplification.md).
- [x] Owner physically reviewed A3.1 usability and supplied the A4 feedback implemented below. This is not acceptance of every offline/device/security case; final checks remain listed under A4.

### Phase A4 — Global UI/UX refinement and alpha feedback collection

Owner-authorized after physical A3.1 review. [Consolidated decisions, superseded specifications and verification](docs/backend/ui-alpha-refinement.md).

- [x] M1: Explore community filters/anonymous discovery, details/history and concise Settings with protected recovery.
- [x] M2: Explicit arbitrary emoji/RGB customization, additive migrations and compact direct-selection review wizard, historical compatibility and tags/comments.
- [x] M3: Compact rankings, collapsing collection, profile and idempotent varied isolated fixtures.
- [x] M4: Configurable global text feedback, private administration, anonymous abuse limits and safe retry.
- [x] Verify rendered Flutter screens, migration/protocol/privacy/fixture/client regressions and Android/Linux releases; update the development APK in place with existing signing identity/data. Owner correction replaces the feedback dock with a floating overlay, without a blank strip; responsive forms reserve horizontal space for it.
- [x] Owner accepted A4 physical UI/UX tests, including feedback submission and its administrative viewer.
- [x] Owner confirms the managed physical restart/offline/reconnection and acceptance matrix in A5.3. Managed Auth/abuse-limit verification and privacy/retention approval are complete. Second physical device testing remains pending; screenshots/shake remain deferred.
- [x] A5.1 implements and rehearses server-enforced current-password verification before password changes; managed configuration remains a deployment gate.

Verified A4 locally on 2026-11-27: **235 Flutter tests pass** (five opt-in placeholders skipped), plus real-font phone/layout captures, strict analysis, formatting and whitespace. Thirty backend unit and thirteen tooling tests pass; backend Ruff and actionlint pass. Disposable A4 API/input/privacy/quota checks, 60 authorization assertions, 1,093 Unicode cases, 465 protocol assertions, eight real Flutter sync tests, 62 community API assertions, real two-account emoji/RGB/review sync and complete private export/restoration pass. The five-account HTTPS development suite verifies retained activity and anonymous feedback/admin access. Unconfigured Android/Linux and configured development releases build; fixture payload isolation is checked on actual APKs. The final development APK is installed with the original certificate/package/code and unchanged first-install timestamp. See the A4 evidence for exact scope, earlier corrected failures, owner feedback correction and acceptance steps. Hosted CI is reported separately after push; no remote success is inferred from local builds.

### A4.1 — Final synchronization UX cleanup

- [x] Remove permanent diagnostics/recovery and routine pending/offline notices from Settings. Automatic sync, retries and durable operations remain unchanged.
- [x] Offer contextual Resolver access only for unresolved rejected/conflicting operations or a blocked private pull. Retain access to exact archived records only when such records exist. Update historical recovery wording for the shared catalogue and anonymous public reviews.
- [x] Verify focused recovery/offline/privacy regressions and the full client suite; build/install the development update in place with the existing identity/data. See [A4.1 evidence](docs/backend/ui-alpha-refinement.md#a41--synchronization-ux-cleanup).

- [x] Owner accepted A4.1 before authorizing A5.1; remaining technical gates are separate.

### A5.1 — Alpha release preparation (historical preparation; deployment continued in A5.3)

Open in-app registration is the owner-approved alpha model. Invitation codes, registration allowlists and manual account provisioning are rejected and supersede the earlier registration restriction gate. Managed deployment and configured APK publication require separate approval.

- [x] Rehearse server-enforced password changes, non-email recovery, authentication/registration abuse limits and current privacy disclosures.
- [x] Prepare ordered non-destructive deployment, backup/restore, deletion/retention, initial administrator and clean catalogue procedures without managed access.
- [x] Prepare gated trusted-HTTPS universal APK publication with public client configuration, signing compatibility and feedback enabled; verify fixture exclusion.
- [x] Owner supplies the genuine bathroom catalogue, standard review tags and suggested emoji sets; integrated and verified in A5.2. Never promote fictional fixtures into the managed catalogue.
- [ ] **Mandatory public-launch gate:** remove the owner's personal support contact from the application, privacy notice and all public distribution materials, replacing it with a dedicated project support contact. The personal contact is approved for the initial alpha only.

See [the exact A5.1 release handover](docs/backend/alpha-release-preparation.md) and [owner content maintenance](docs/content-maintenance.md). Privacy distinguishes public anonymous reviews from private history, email and feedback; recovery uses a saved 256-bit code rather than unverified email ownership. Existing production verification/recovery remains a separate configuration. Initial-alpha support is centralized for later replacement.

Verified locally on 2026-11-27: **238 Flutter tests pass** (five opt-in placeholders skipped), rendered 320/390dp password forms in both themes with enlarged text/keyboard insets, strict analysis/formatting, **31 backend unit** and **14 tooling tests**, Ruff and actionlint. Actual isolated HTTP tests deny missing/wrong current-password changes and verify fresh recovery proof, rotation/consumption, native administrator reset retaining the same UUID, scoped deletion preserving another account's history, native Auth deletion, blocked email recovery/OTP and signup limits. A4 feedback/input/privacy/quota tests pass; 62 community API assertions and real two-account Flutter visibility/offline-cache tests pass. The five-account retained development HTTPS suite passes, including recovery-code generation without replacing primary credentials. The generated deployment plan executes twice safely and populated schema/data/private feedback/recovery/synchronization export-restoration verifies rows, sequence, receipt/cursor continuation and restored clock collision. Earlier full protocol/Unicode runs also passed during preparation; new test-fixture/import/environment errors were corrected and rerun, not counted as successful checks.

The trusted-HTTPS configured universal alpha `0.1.0-alpha.1036` is built privately, signature/package/AOT verified and scanned for fixture/local-TLS/credential exclusion; it is neither published nor installed against managed Supabase. The separate isolated development `0.1.0-dev-a51.1023` is installed with `adb install -r`, original certificate/package/code and first-install timestamp `2026-11-26 22:40:55`; no uninstall, reseed or data clear. The rendered phone shows anonymous Explore with retained fictional entries and the owner-created `aaa` bathroom. Managed configuration, existing fictional-state handling, approved retention periods, genuine owner content, physical security/offline/second-device acceptance and first configured publication remain release gates. Repository configured-publication gate remains unset. A5.1 makes no managed request and starts no further milestone.

### A5.2 — Final alpha content and branding integration

Owner-approved catalogue, content standards and royal toilet-throne artwork, completed before the separate A5.3 managed deployment authorization. Configured publication remains gated.

- [x] Version the 34 exact genuine official entries with permanent key-derived identities; prepare an operator-only, dry-run/idempotent/conflict-detecting importer and private backup-preserved registry, with no fictional activity or client import API.
- [x] Integrate 40 humorous tags, 40 emoji suggestions, 18 arbitrary-RGB-compatible swatches and ten absolute distinct-discovery decorative thresholds. Preserve draft stability, custom/search/history/legacy identities and rating descriptions.
- [x] Preserve original PNG and generate reproducible Android adaptive/legacy launcher and native splash resources; set Bath Royale launcher name without changing package/signing/version rules or ordinary screens.
- [x] Verify 242 Flutter, 33 backend and 14 tooling tests, strict analysis/format/lint, disposable catalogue import/corrections/conflicts/restoration, existing community API/real-client privacy regressions, responsive light/dark captures and Android/Linux releases. Keep the retained development backend intact.
- [x] Install `0.1.0-dev-a52.1023` in place on SM A166B using the original certificate/package/code; retain app ID 10419 and first-install timestamp. Inspect actual One UI launcher label/icon and native cold-start splash, restored account and visible owner-created activity. No uninstall, data clear or reseed.
- [x] Prepare final non-destructive managed deployment, genuine-catalogue import and gated single-APK handover; enumerate privacy/retention/support/publication decisions and preserve the dedicated-contact public-launch gate.

See [A5.2 evidence and device status](docs/backend/final-alpha-content.md), [content maintenance](docs/content-maintenance.md) and [the final deployment approval gate](docs/backend/alpha-release-preparation.md#a52-final-deployment-handover--awaiting-owner-approval). No managed access, configured publication, fixture reseed or cost was incurred.

### A5.3 — Managed alpha deployment and release acceptance (initial alpha completed)

Managed deployment and automated acceptance are verified. The final local checks pass: 242 Flutter, 38 backend and 14 tooling tests, strict analysis/format/lint and Linux/Android releases. The owner confirmed physical acceptance and authorized initial-alpha publication on 2026-11-27. Second physical device testing remains pending; see [exact deployment/restoration/publication evidence](docs/backend/managed-alpha-acceptance.md).

- [x] Inspect the actual existing Free project/schema/history/data; take an owner-encrypted, quiesced native backup and verify isolated restoration before migration. Preserve uncertain/owner activity and development namespaces.
- [x] Apply non-destructive migrations through 017; hide the historically identified fictional sample through protected moderation and retire its exact accounts without deleting legacy records.
- [x] Dry-run/import the 34 exact official catalogue entries; verify stable UUIDs, names, emoji/RGB/classification, idempotency, anonymous visibility and no fabricated activity on official entries.
- [x] Configure the approved open alpha Auth policy and pass 104 actual managed API checks. Provision administration/creation only from the owner's independently proven UUID.
- [x] Resolve the final encrypted-backup restoration failure by reconstructing two exact source CHECK definitions, with regression coverage and unchanged strict preservation checks; pass fresh isolated restore/verification and 86 runtime/protocol assertions. No live project access during the blocker resumption.
- [x] Prepare and install signed managed alpha 1038 in place, preserving identity/data; prepare public Actions configuration, release notes, manual retention/backup duties and privacy notice. Publication stayed disabled until separate owner approval; unconfigured CI builds are not distributed.
- [x] Owner confirms physical restart/offline/reconnection/visit/feedback/replacement-recovery-code acceptance. This is owner-reported acceptance, separate from automated checks.
- [ ] Second physical Android device acceptance; no device is available. The owner authorizes initial-alpha publication with this explicitly pending limitation.
- [x] Owner approves final configured GitHub publication after acceptance.
- [x] Publish and independently verify signed configured universal [alpha 1039](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1039) and checksum. [Release CI 45965320805](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45965320805) passed for source `6bb49a1`; anonymous asset download, signature/package/version/AOT, real managed HTTPS public configuration and fixture/credential exclusion passed. Close `ALPHA_RELEASE_APPROVED=false` after this authorized release; subsequent documentation pushes validate without distributing APKs.

### Private alpha release gates and subsequent scope

- [x] Verify managed open registration with server-side abuse limits in A5.3. No invitations, allowlists or manual account approval; configured publication remains gated.
- [x] Approve and implement bounded A2 private account synchronization below. Guest association, shared catalogue and public identity remain deferred; A2 supersedes only the private-sync portion of historical Phase 2.3C.
- [x] Address accumulated Explore + / empty-state / filter / fictional-content feedback through A4. Remove the review FAB and distinguish personal discovery from published community scores. Owner physical acceptance of the final correction is recorded above.
- [x] Apply and automatically verify the managed migrations, Auth protections, private deletion/recovery, encrypted backup/restoration and approved manual retention/privacy procedures in A5.3. Owner physical acceptance is confirmed; second physical device testing remains pending. Verified-email authentication/recovery remains a mandatory public-launch gate.

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
- [x] Verify predictable preview versioning and APK signing; provide automatic GitHub development pre-release distribution (historical milestone; superseded by configured-alpha-only distribution and owner-approved preview release/asset cleanup, with tags retained).
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

### Intermediate maintenance — Optimized Android previews

- [x] Verify optimized universal release preview locally and through hosted publication, preserving signing, identity, versioning and checksum distribution. Hosted run [45859523546](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45859523546) passed and public preview 1025 independently verified: 56,837,558 bytes, 63.8037% smaller than debug preview 1024. All 170 Flutter regressions, strict analysis, formatting, actionlint and five preview-tooling tests pass.
- [ ] Owner physical in-place update and existing SQLite data acceptance.

This maintenance milestone does not start Phase 2.3B or production signing. See [preview operations](docs/android-previews.md#optimized-preview-maintenance-after-phase-23a).

### Phase 2.3B — Production authentication and device lifecycle

- [x] Implement optional email/password authentication through the official SDK, secure session persistence and a private Profile account interface; retain guest startup with no backend.
- [x] Implement approved offline local account access, isolated account retention, logout to original guest and guarded draft/failed-write transitions; keep domain synchronization disabled.
- [x] Verify real registration, required confirmation, recovery and password change with fictional accounts and local email capture in a new isolated installation.
- [x] Verify formatting, unchanged exact strict analyzer baseline, all 178 ordinary Flutter tests (170 retained plus eight new), one separate real Auth suite, all 25 offline backend tests, Ruff, actionlint and five preview-tooling tests. Linux/Android debug and configured release builds pass; universal release identity/AOT/non-debuggable status and existing preview certificate verified. An isolated Linux platform keyring write/read/delete probe passes.
- [ ] Owner acceptance of Android Keystore lifecycle and Linux desktop keyring lock/unlock, account offline/reconnection/logout flows and retained drafts on physical devices.
- [ ] Resolve zero-recurring-cost public email delivery and deploy HTTPS/public client configuration; confirmation remains required.

See [production authentication](docs/backend/production-authentication.md). The owner approved email/password, secure persistent sessions, offline account access and isolated local retention after logout. Domain account views remain local-only; remote cache composition, private synchronization, guest association and public identity remain unapproved. No managed or preserved migration/sync installation was accessed. Phase 2.3C remains unstarted.

### Phase 2.3B follow-up — Authentication hardening and device-test preparation

- [x] Reproduce revoked-session restoration after failed secure deletion, disposed submission controllers, non-due renewal churn and missing failed-open retry; add targeted regressions and durable fail-closed restoration permission without placing secrets outside platform storage.
- [x] Separate private Profile authentication flows, show private email without UUIDs, preserve draft/failed-write guards and recover latest-account/guest selection after store failures.
- [x] Prepare an isolated USB/HTTPS release target and [device procedure](docs/android-auth-device-testing.md), preserving the package, preview certificate, installed version-code compatibility and guest-only public workflow.
- [x] Verify all 189 ordinary Flutter tests (all 178 retained plus 11 focused additions), locked dependencies, formatting, unchanged strict analyzer baseline, 25 offline backend tests, Ruff, actionlint and five preview-tooling tests. Real Auth passes directly and through the local TLS gateway; separate certificate/hostname/route checks pass. Standard configured Android release and private HTTPS Android/Linux release targets build; private APK package/certificate/code/AOT verified.
- [x] Prepare the authorized physical Android session: verify installed package/certificate/key, reuse version code 1023, build/verify/install private release with `adb install -r`, retain app ID/first-install timestamp and leave isolated Auth/Mailpit/HTTPS/USB services available. Add a local phone inbox helper with automatic verification-link mapping and recipient isolation.
- [ ] Owner verification of physical Android data preservation, Keystore/restart/offline/revocation and phone flow acceptance; actual Linux desktop keyring lock/unlock. Private code-1023 Auth APK is installed in place on the authorized phone, with matching certificate and unchanged app ID/first-install timestamp. Manual physical acceptance remains pending; the isolated backend and USB inbox helper are left available.

Executed on 2026-11-26. The private APK uses local build-only code 1 and was not installed or published. The isolated Auth backend was stopped after hardening verification and has now been restarted for the prepared physical session; independent data is retained and no managed/preserved migration/sync backend was accessed. Local OpenSSL source-build attempts were cancelled in favour of the locked binary cache; early test-only import/override errors were corrected before the final passing checks.

See the [review findings and storage limitations](docs/backend/production-authentication.md#hardening-review-of-commit-871634d). Upgrading the pre-hardening session requires one fresh login; guest/account data remains intact. No private synchronization, guest association, public identity, managed-project access or deployment is included. Phase 2.3C remains unstarted.

### Phase 2.3C — Historical consent/association/private-sync proposal

A2 above implements and verifies the private synchronization, Unicode and metadata-portability portions. The combined guest-association proposal below is not approved or started; do not infer permission to associate/import guest records.

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
