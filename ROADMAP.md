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

Local verification: 105 tests pass, including structured sequences, equivalence, custom creation, comments/drafts/cancellation, v3 upgrades and persistence, alongside all existing regressions. Both debug builds and the exact strict-analysis gate pass. Flutter-rendered 320/390dp light/dark layouts with enlarged text were inspected. Backend work has not started; classification remains exploratory and public catalogue/contribution direction is preserved.

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

- All published bathrooms are publicly discoverable; private bathrooms are removed from the vision. Personal history may remain private independently.
- Validate/moderate user proposals before publication. Reward approved contributions, preserving original attribution through administrator validation/promotion. XP, achievements and recognition are possibilities; exact mechanics remain open.
- Explore inside/outside University of Aveiro presentation without deciding names, rules or geographic hierarchy. Model membership, origin/attribution and verification as distinct concepts, allowing a user-contributed university bathroom. Consider other institutions, campuses and cities.
- No visibility categories, moderation, authentication, permissions, contribution rewards, XP, achievements or power-ups in Session 4A.

Rankings/collection verification: all 33 tests, formatting and Linux/Android debug builds pass. Analysis reports only 18 Material import deprecation notices. No schema changes were needed.

### Final Phase 1 acceptance

The local prototype acceptance criteria are satisfied: all 36 automated tests, formatting and Linux/Android debug builds pass. Analysis reports only 20 known Material import deprecations. Hidden tag validation, tab-specific creation, ranking explanations and the local profile are stabilized. See [audit evidence and deferred debt](docs/phase-1-audit.md). This completion does not complete release preparation or authorize community/backend implementation.
