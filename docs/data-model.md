# Local data model

The prototype restores and persists local SQLite data. See [storage architecture and migrations](storage.md). These rules are not an authentication or backend contract.

## Bathrooms, visits and reviews

- `Bathroom` contains shared identity, name and creator attribution. Creating one does not create a visit or favourite.
- `Visit` has a stable ID, bathroom ID, user ID and timestamp. A user may visit the same bathroom repeatedly. A visit without a review is a complete experience. Duplicate IDs and identical user/bathroom/timestamp records are rejected.
- Every `Review` references exactly one visit with the same bathroom and author. A visit has at most one review. Review identity, visit association, author, bathroom and creation time cannot change on edit; update times cannot go backwards. Ratings are finite 0–5, paper scores 0–2 and other category scores 0–4. Tags are immutable copies.
- Favourites are independent personal flags. The displayed latest visit and visit count are derived from visit records for the current user. Explore's latest-visit ordering uses that derived timestamp, with missing values last.

State validates references, uniqueness and ownership on construction and mutation. Creating a visit with a review validates both before changing state and sends one notification. An existing unreviewed visit can receive one review. Editing does not create or change a visit. Local ownership checks are not security controls for a future backend.

## Experience

Registering a visit immediately updates history and the personal collection. A dismissible invitation offers an optional review or undo. Undo removes only the exact newly registered visit if it still exists and has no review; it cannot remove a review or change another visit or favourite. Explicit removal is available from history; a confirmation explains when the associated review will also be removed. Removing the last visit removes the bathroom from the visit-based collection, without changing its favourite.

A direct review can select an existing unreviewed visit or create a new visit atomically on save. Cancelling the form does not create a visit. A review opened from a visit is associated with that visit; cancelling leaves the visit intact. There are no pending statuses or reminders. Rating stars, the decimal slider, tags and original humorous category descriptions remain available.

## Ratings and sample data

The personal review is the current user's latest reviewed visit by visit timestamp, with visit ID breaking equal-time ties. Delayed submission or editing an older experience does not promote it. Community rating is the mean of individual reviews, including repeated visits. No review is distinct from a zero rating. Cards and personal filters continue to use personal reviews; favourites use the independent flag.

The original five sample reviews each have exactly one matching sample visit at the original sample date. The sixth bathroom has neither. Data and theme settings survive restarts; sample data is seeded only at first initialization. New entity identifiers use UUID v4.

## Verification

Regression tests cover optional repeat visits, visit chronology, derived timestamps, favourites, ownership, atomic creation, association, rapid-tap duplicate prevention, editing, deletion, undo, cancellation, collection, search and sorting. All 29 tests pass, including restart, migration, storage failure and transaction rollback coverage. Formatting and Linux/Android debug builds pass. Analysis exits with 16 Material import deprecation notices and no other diagnostics. Multiplayer policy, moderation and ranking formulas remain open.

## Derived rankings and collection

Rankings use all reviews by the current user for personal means, or all local reviews for community means. Each review has equal weight. All five metrics use their original scales (overall 5, paper 2, other categories 4); missing reviews are excluded and real zero scores remain valid. Ties use case-insensitive bathroom name then ID in both directions. This differs from the latest personal experience shown on Explore cards.

Discovery means at least one visit by the current user. Progress divides discovered bathrooms by the current catalogue size (zero for an empty catalogue); statistics count unique visited bathrooms, all personal visits, personal reviews and independent favourites. History sorts by visit timestamp descending, then visit ID. None of these derived views changes schema version 2 or stored records. Suggested tags describe characteristics, and custom input is revealed by an action chip. Existing custom tags remain editable.
