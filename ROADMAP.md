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
- [ ] Create bathrooms with appropriate validation.
- [ ] Improve search, sorting, filters and favourites.
- [ ] Persist local data and define a migration strategy.
- [ ] Implement rankings and a personal collection.
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

Bathroom entities, individual author-owned reviews and per-user favourites/latest visits are separated in memory. Multiple reviews, latest personal ratings and community means are covered by unit and widget regression tests. Cards and filters retain their existing personal-rating behavior. See [data-model semantics](docs/data-model.md). Details and review forms are now implemented; the remaining Phase 1 milestones remain open.
