# Local data model

Phase 1 keeps all data in memory. These are minimal prototype semantics to revisit before multiplayer implementation, not a backend contract.

## Records and ownership

- `Bathroom` contains only shared facility identity, name and `createdBy` attribution. Creating a facility does not grant exclusive control over other people's reviews or personal records. Facility editing and deletion rules remain open.
- `Review` is an immutable individual experience with a stable ID, bathroom ID, author ID, creation/update timestamps, overall rating, category scores and descriptive tags. Any author can have multiple reviews of the same facility, including on the same day. Scores are validated: overall 0–5 (finite), paper 0–2, other categories 0–4. Tags are copied into an unmodifiable list.
- `BathroomActivity` is private to a `(userId, bathroomId)` pair. It holds a favourite flag and an optional latest explicit visit timestamp. Favouriting does not imply visiting or reviewing. Reviewing does not automatically record a visit; a visit does not require a review. Repeated or older visit timestamps leave the latest visit unchanged. This is not a visit log or visit counter.

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

The form requires an overall finite score between 0 and 5 (Portuguese decimal commas are accepted) and explicit choices for all four categories. Optional comma-separated tags are trimmed and deduplicated; input allows at most ten nonempty tags of up to thirty characters, with no embedded newlines. Edits preload all values; returning without saving leaves state untouched. Saving notifies Provider and immediately recomputes details, cards and filters. Visit recording is a separate action using the current time. All data still resets when the process restarts.

## Verification

Verified on 2026-11-25 in the existing flake/direnv environment: formatting check (17 Dart files unchanged), all 11 unit/widget tests, Linux debug and release builds, and `git diff --check`. `flutter analyze` exits with status 1 for nine existing Material import deprecation notices; it reports no other issues. The initial sandboxed test command could not write SDK telemetry metadata; rerunning with the required SDK access succeeded.

Details/review milestone: formatting, all 16 unit/widget tests and Linux debug/release builds verified. Analysis reports only the same Material import deprecation, now at 12 import sites including the new pages/tests. Initial widget tests exposed off-screen test taps and a visit snackbar covering the form action: the form now uses a scroll view retaining all fields, the snackbar is dismissed on opening the form, and the tests scroll and settle before interacting.
