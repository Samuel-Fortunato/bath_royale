# Changelog

## Unreleased

- Cancel superseded routine Android previews while isolating each explicit pre-release publication request.
- Report CI status without waiting during routine development; prefer available development tools directly and preserve sandboxing.

- Add Nix-locked GitHub Actions checks and Android preview APK artifacts on `main` pushes and manual runs, with dependency caching and 14-day retention.
- Preserve Android preview signing through an approved Actions secret, verify APK identity/certificate/version, and add opt-in manual GitHub pre-releases.
- Gate analysis with a tested, exact baseline for existing Material imports; retain all other diagnostics.
- Document phone installation and preview versioning; authorize automatic pushes of completed, verified tasks to the existing upstream.
- Verify the first hosted CI run, all 40 tests and the signed APK artifact; refresh action pins to current Node 24 releases after GitHub's runtime notice.

- Complete the Phase 1 local prototype audit with 36 tests and Linux/Android debug builds; document accepted Material deprecations and deferred release work.
- Keep custom tag validation visible when input is hidden, refresh its label, and restrict bathroom creation to Explore.
- Add a useful local profile, accessible icon labels and explicit mean-versus-latest personal rating explanations.

- Add personal/community best and worst rankings across overall and category ratings, with counts and detail navigation.
- Expand collection discovery, catalogue progress, personal statistics and chronological visit history.
- Reveal custom tag input on request and refresh suggested tags and experience selection wording.
- Record future catalogue and contribution policies as documentation-only direction.

- Persist local entities, favourites and theme in versioned SQLite storage; restore state and seed samples only once.
- Use UUIDs for new records, visit chronology for personal ratings and a rapid-tap visit guard.
- Add migration, restart, transaction rollback and storage-failure regression coverage; preserve files on startup errors.

- Link each review to one visit and support optional reviews, repeat visits and derived visit counts.
- Add visit history, a personal collection, optional review invitations, safe undo and confirmed removal.
- Create visits atomically with direct reviews or associate reviews with existing visits.

- Refine review entry with interactive stars, decimal adjustment, rating feedback and editable suggested/custom tags.
- Compact Explore search, sorting and filters, and improve visit status presentation.
- Cover review controls, visit undo and mobile/desktop Explore flows with regression tests.

- Add visit confirmation with haptic feedback and an undo action that preserves favourites and later visits.
- Implement the + action and responsive bathroom creation with name validation, creator attribution and normalized duplicate-name protection.
- Add Explore name search and sorting by community rating, personal rating, name and latest explicit visit, with deterministic ties and missing values last.
- Add result counts, empty states, search/filter reset and explicit personal/community rating labels; preserve humorous rating descriptions and favourites.
- Verify twenty automated tests, formatting, Linux debug/release builds, Android debug APK and a connected physical Android launch.


- Align Android with the installed Flutter 3.50.1 templates: Gradle 9.5.0, AGP 9.3.1, KGP 2.4.20 and Java 17 compiler options.
- Record the existing Nix Android SDK/NDK/Java environment and Nix-provided aapt2 override; preserve application identity and Flutter compatibility flags.
- Ignore generated Android build directories and verify the debug APK with dependency validation enabled.

- Add responsive bathroom details with community averages, review counts, personal history, individual ratings and dates.
- Add validated review creation and owner-only editing with existing humorous category descriptions.
- Add favourite and explicit visit actions in details, with immediate card and filter updates.
- Cover navigation, review validation, repeat reviews, editing, cancellation and narrow-screen layouts in tests.

- Separate shared bathrooms, author-owned reviews and personal favourites/latest visits in memory.
- Support repeat reviews, latest personal ratings and independent community averages; retain sample cards, filters and humorous descriptions.
- Validate review scores, references and local ownership; add model and reactive UI regression tests.
- Document local data semantics, NixOS executable discovery and concise terminal summaries.

- Correct review updates, favourite filtering and unreviewed bathroom cards.
- Add regression coverage for prototype state and filters.
- Document the Flutter 3.50 Material deprecation and migration considerations.
