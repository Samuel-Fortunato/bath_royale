# Local data model

Phase 1 keeps all data in memory. These are minimal prototype semantics to revisit before multiplayer implementation, not a backend contract.

## Records and ownership

- `Bathroom` contains only shared facility identity, name and `createdBy` attribution. Creating a facility does not grant exclusive control over other people's reviews or personal records. Facility editing and deletion rules remain open.
- `Review` is an immutable individual experience with a stable ID, bathroom ID, author ID, creation/update timestamps, overall rating, category scores and descriptive tags. Any author can have multiple reviews of the same facility, including on the same day. Scores are validated: overall 0–5 (finite), paper 0–2, other categories 0–4. Tags are copied into an unmodifiable list.
- `BathroomActivity` is private to a `(userId, bathroomId)` pair. It holds a favourite flag and an optional latest explicit visit timestamp. Favouriting does not imply visiting or reviewing. Reviewing does not automatically record a visit; a visit does not require a review. Repeated or older visit timestamps leave the latest visit unchanged. This is not a visit log or visit counter.
- Visit undo restores the previous timestamp only if the recorded timestamp is still current, while preserving the current favourite flag.

`AppState.currentUserId` is a fixed local identity, not authentication. State validates unique bathroom/review IDs and bathroom references. `saveReview` permits only the current author's records; updates preserve ID, bathroom, author and creation time, and cannot move the update timestamp backwards. Other authors' records can be seeded to exercise community behavior. These local checks are not security controls for a future backend.

All entities and exposed source collections are immutable or unmodifiable. Mutations go through state methods and notify Provider listeners. Creating another state instance does not share mutable sample data. There is no persistence, synchronization, authentication or backend.

## Personal and community ratings

`BathroomEntry` derives display data from the separate records:

- The personal review is the current user's latest by creation time, with lexicographically greater review ID breaking equal-time ties. Editing an older review does not promote it above a newer experience.
- The community rating is the arithmetic mean of every individual review's overall rating, across all authors and repeat reviews. `reviewCount` counts reviews, not users. Repeated experiences therefore have repeated weight. Updating an existing review replaces its contribution without increasing the count.
- No reviews means a null community rating and zero count. No personal review means a null personal review, even if other users have reviewed the facility. A genuine zero rating remains a rating.

Cards, rating/category filters and reviewed/unreviewed filters continue to use the personal review, preserving the existing appearance and humorous descriptions. Favourite filtering uses only the current user's activity. Details display community aggregates separately from personal ratings; future ranking or anti-abuse formulas remain separate product work. Category descriptions belong to individual reviews, so fractional averages are never rounded into invented descriptions.

## Sample data and scope

The original six facilities and five ratings are retained as separate records. The five original experiences are explicitly seeded with visits on a fixed sample date; the sixth has neither review nor visit. Favourites start empty. Bathroom details expose favourites and explicit visit recording. Review forms create individual experiences and edit only current-user reviews, preserving record identity and creation dates.

Future work must decide review/visit linking, detailed visit history, deletion and moderation rules, aggregate weighting, authentication, storage and migration before implementing those behaviors.

## Details and review forms

Tapping a card opens a scrollable details route with a constrained desktop width. It shows community average/count, latest personal rating, latest explicit visit, personal review history and all individual community reviews (including the current user), sorted newest first. Reviews retain the humorous category descriptions, tags, creation dates and edit dates. Only owned reviews expose edit actions.

The form requires an explicit overall score between 0 and 5: stars select half points, the slider selects tenths, and zero has its own action. Existing scores retain their precision until changed. All four categories require explicit choices. Suggested and custom tags can be selected or removed; up to ten nonempty tags of at most thirty characters are allowed, without embedded newlines. Edits preload all values; returning without saving leaves state untouched. Saving notifies Provider and immediately recomputes details, cards and filters. Visit recording is a separate action using the current time. All data still resets when the process restarts.

## Verification

Verified on 2026-11-25 in the existing flake/direnv environment: formatting check (17 Dart files unchanged), all 11 unit/widget tests, Linux debug and release builds, and `git diff --check`. `flutter analyze` exits with status 1 for nine existing Material import deprecation notices; it reports no other issues. The initial sandboxed test command could not write SDK telemetry metadata; rerunning with the required SDK access succeeded.

Details/review milestone: formatting, all 16 unit/widget tests and Linux debug/release builds verified. Analysis reports only the same Material import deprecation, now at 12 import sites including the new pages/tests. Initial widget tests exposed off-screen test taps and a visit snackbar covering the form action: the form now uses a scroll view retaining all fields, the snackbar is dismissed on opening the form, and the tests scroll and settle before interacting.

## Bathroom creation and Explore

The + action opens a cancellable, scrollable creation form. Names are required, limited to 100 characters, and reject control characters. Names are trimmed and repeated whitespace collapses to one space. State rejects existing names case-insensitively with the same whitespace normalization, including a second submission. This conservative local duplicate rule uses the only available identity field: users should include a building/floor or other distinguishing information for separate facilities. It does not detect spelling variants or physical duplicates; structured location identity remains future product work.

Creation generates a collision-free local ID and attributes the bathroom to the current user. It notifies listeners without creating a review, favourite or visit, then opens details. The source bathroom collection remains unmodifiable to callers.

Explore matches a case-insensitive normalized name substring and combines it with the existing personal filters. Name sorting is ascending; community rating, latest personal rating and explicit latest visit sort descending with missing values last. Ties use case-insensitive name then ID. Search/filter reset preserves the selected sort. Cards label community averages separately from personal scores and humorous category descriptions.

Creation/Explore verification on 2026-11-25: all 20 tests pass, formatting (23 Dart files unchanged), Linux debug/release builds, Android debug APK and diff whitespace checks pass. Physical SM A166B launch synchronized successfully and exposed a Dart VM service after an earlier owner-reported DevFS disconnect. Automated widget coverage includes mobile (390 px) and desktop (1200 px) creation, required/duplicate validation, search and reset; model tests cover creation isolation, notifications and sort/null/visit behavior. Analysis reports only Material import deprecations (14 sites, exit 1). No persistence or backend was added.

## Mobile interface refinement

Explore offers compact search, a sort menu, quick filters and a filter sheet; active filters appear first. Details show the latest explicit visit and offer conditional undo without replacing favourites or newer visits. Review categories retain their original descriptions. Verification: 22 tests, Linux debug and Android debug builds; analysis reports the 14 previously documented Material import deprecations.
