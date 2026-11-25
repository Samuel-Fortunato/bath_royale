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
- [x] Verify predictable preview versioning and APK signing; provide opt-in manual GitHub pre-release distribution.
- [x] Document phone installation, data-preserving update requirements and automatic verified commits/pushes.

See [Android preview operations](docs/android-previews.md). Production signing and store release preparation remain open. This milestone does not start backend implementation.

Verified on 2026-11-25: local formatting, strict analysis, all 40 tests, actionlint, Nix flake checks and Android preview compilation pass. [The first GitHub Actions run](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45604860872) independently passed the checks, built APK version `0.1.0-preview.1` / code `1001`, verified the existing signing certificate and uploaded the APK/checksum artifact. Optional pre-release publishing is implemented and linted; it has not been invoked. A physical in-place installation of the CI APK remains a separate device check.

## Phase 2 — Community functionality

- [ ] Evaluate backend options, including the preferred Supabase and PostgreSQL candidates, before choosing an architecture.
- [ ] Implement authentication and a shared bathroom database.
- [ ] Support community reviews and cloud synchronization, including local data migration and conflict handling.
- [ ] Add moderation and reporting.

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

- Curate an official catalogue and validate/moderate public community bathroom proposals.
- Support private custom bathrooms and personal tags without automatically adding tags to the shared catalogue.
- Consider gamification/reputation privileges for public bathrooms, community tags and eventual contribution validation, combined with moderation, duplicate prevention, contribution quality and submission limits.
- Keep private experience recording available without earned privileges. Exact progression, permissions and moderation workflows remain undecided. Phase 1 local experimentation remains unrestricted.

Rankings/collection verification: all 33 tests, formatting and Linux/Android debug builds pass. Analysis reports only 18 Material import deprecation notices. No schema changes were needed.

### Final Phase 1 acceptance

The local prototype acceptance criteria are satisfied: all 36 automated tests, formatting and Linux/Android debug builds pass. Analysis reports only 20 known Material import deprecations. Hidden tag validation, tab-specific creation, ranking explanations and the local profile are stabilized. See [audit evidence and deferred debt](docs/phase-1-audit.md). This completion does not complete release preparation or authorize community/backend implementation.
