# Roadmap

The phases describe intended sequencing, not a fixed specification. Unconfirmed details are proposals and may change with product decisions and implementation findings. Check items only when implemented and verified.

## Phase 0 — Development environment (completed)

- [x] Configure the project Nix flake and direnv integration.
- [x] Establish a Flutter development environment and complete Linux debug and release builds.

## Phase 1 — Complete the local prototype

- [x] Audit the existing prototype and fix bugs, including review updates, favourite filtering and unreviewed bathroom presentation.
- [x] Investigate the Flutter 3.50 Material deprecation; document migration considerations.
- [x] Separate bathroom entities from individual reviews and define local ownership and visit semantics.
- [x] Implement bathroom details.
- [x] Create and edit reviews while preserving the rating descriptions.
- [x] Create bathrooms with appropriate validation.
- [x] Improve search, sorting, filters and favourites.
- [ ] Persist local data and define a migration strategy.
- [ ] Implement rankings; expand the visit-based personal collection as the prototype evolves.
- [ ] Add automated tests for models, state and important user flows.
- [ ] Verify formatting, analysis, tests and appropriate builds; update documentation.

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

Verified in memory: validated creation with normalized duplicate-name prevention, name search, four deterministic sort orders, explicit personal/community labels, filter reset and empty states. Twenty unit/widget tests pass, including 390 px and 1200 px creation flows. Formatting, Linux debug/release and Android debug APK builds pass. Analysis retains only the documented Material import deprecations. Persistence, broader test coverage and release preparation remain open.

### Mobile UI refinement

Review ratings and tags, explicit visit feedback and undo, and compact Explore controls are implemented and covered by regression tests. Linux and Android debug builds are verified. Broader responsive design and release preparation remain open.

### Visit and review integration

Every review belongs to one visit; visits may stand alone. The in-memory prototype supports repeat visits, a visit-based collection, optional reviews, history, conditional undo and confirmed removal. Twenty-one tests and Linux/Android debug builds pass; analysis reports the known Material import deprecations. Persistence and migration remain open.
