# Local data model

Current account/community semantics are documented in [A3.1](backend/community-simplification.md). Normal workflows use one shared catalogue, classified official/community. New reviews use shared bathroom identities and are automatically public and anonymous after disclosure; historical private reviews retain their visibility. Public `CommunityReview` scores have independent per-review public IDs, no reusable author identity and no visit/date/email fields. Private `Review`/`Visit` rows retain ownership and original references; no fake visits represent public content. Legacy bathrooms and links remain intact outside normal workflows. Published-only community scores replace the earlier local approximation. Earlier prototype sections below remain historical.


The prototype restores and persists local SQLite data. See [storage architecture and migrations](storage.md). These rules are not an authentication or backend contract.

## Bathrooms, visits and reviews

- `Bathroom` contains shared identity, name, creator attribution, emoji and a curated accent index (0–5). Missing legacy identities derive deterministically from ID/sample name and are persisted by schema v3; no render-time randomization. Creating one does not create a visit or favourite.
- `Visit` has a stable ID, bathroom ID, user ID and timestamp. A user may visit the same bathroom repeatedly. A visit without a review is a complete experience. Duplicate IDs and identical user/bathroom/timestamp records are rejected.
- Every `Review` references exactly one visit with the same bathroom and author. A visit has at most one review. Review identity, visit association, author, bathroom and creation time cannot change on edit; update times cannot go backwards. Ratings are finite 0–5, paper scores 0–2 and other category scores 0–4. Tags are immutable copies.
- Favourites are independent personal flags. The displayed latest visit and visit count are derived from visit records for the current user. Explore's latest-visit ordering uses that derived timestamp, with missing values last.

State validates references, uniqueness and ownership on construction and mutation. Creating a visit with a review validates both before changing state and sends one notification. An existing unreviewed visit can receive one review. Editing does not create or change a visit. Local ownership checks are not security controls for a future backend.

## Experience

Registering a visit immediately updates history and the personal collection. A dismissible invitation offers an optional review or undo. Undo removes only the exact newly registered visit if it still exists and has no review; it cannot remove a review or change another visit or favourite. Explicit removal is available from history; a confirmation explains when the associated review will also be removed. Removing the last visit removes the bathroom from the visit-based collection, without changing its favourite.

A direct review creates a new visit atomically on successful save, even when older unreviewed visits exist. Older visits can be reviewed only by an explicit history/experience action. Cancelling the form does not create a visit. A review opened from a visit is associated with that visit; cancelling leaves the visit intact. There are no pending statuses or reminders. The three-step review wizard retains one draft across Global, Detalhes and Etiquetas. A single adjustable star strip selects 0–5 in tenths, distinguishing unanswered from explicit zero; tags and all original humorous category descriptions remain available. There is no visit-selection sheet or Alterar control; editing and visit-specific entry keep their association fixed. System back first moves to the previous wizard step; leaving a changed draft requires discard confirmation. Custom tag creation remains available locally through an isolated UI capability flag, without introducing permissions.

## Ratings and sample data

The personal review is the current user's latest reviewed visit by visit timestamp, with visit ID breaking equal-time ties. Delayed submission or editing an older experience does not promote it. Community rating is the mean of individual reviews, including repeated visits. No review is distinct from a zero rating. Explore cards prioritize the community mean/count and separately label the latest personal review. Personal rating filters continue to use personal reviews; discovery filters use actual personal visits. Favourites use the independent flag.

The original five sample reviews each have exactly one matching sample visit at the original sample date. The sixth bathroom has neither. Data and theme settings survive restarts; sample data is seeded only at first initialization. New entity identifiers use UUID v4.

## Original model verification (historical)

Regression tests cover optional repeat visits, visit chronology, derived timestamps, favourites, ownership, atomic creation, association, rapid-tap duplicate prevention, editing, deletion, undo, cancellation, collection, search and sorting. All 29 tests pass, including restart, migration, storage failure and transaction rollback coverage. Formatting and Linux/Android debug builds pass. Analysis exits with 16 Material import deprecation notices and no other diagnostics. Multiplayer policy, moderation and ranking formulas remain open.

## Derived rankings and collection

Rankings use all reviews by the current user for personal means, or all local reviews for community means. Each review has equal weight. All five metrics use their original scales (overall 5, paper 2, other categories 4); missing reviews are excluded and real zero scores remain valid. Ties use case-insensitive bathroom name then ID in both directions. This differs from the latest personal experience shown on Explore cards.

Discovery means at least one visit by the current user. Progress divides discovered bathrooms by the current catalogue size (zero for an empty catalogue); statistics count unique visited bathrooms, all personal visits, personal reviews and independent favourites. History sorts by visit timestamp descending, then visit ID. These derived views do not mutate stored records. The identity extension uses schema version 3. Suggested tags describe characteristics, and custom input is revealed by an action chip. Existing custom tags remain editable.

The personal ranking explanation explicitly contrasts averages with the latest reviewed visit shown on Explore cards. The local profile derives favourites and recent activity without new records. See [Phase 1 acceptance](phase-1-audit.md) for final verification and deferred debt.

## Phase 1.6 presentation

Bathroom details have independent Summary, Reviews and Personal Visits tabs. Summary defaults to all locally available reviews (including own, once), with numeric category means on their original scales. Personal scope uses the existing latest-reviewed-visit derivation and that visit's date, with original category descriptions. Histories retain their existing ordering, edit ownership and confirmed deletion behavior, using lazy lists with independent scroll positions. Closing, swiping or backing out of the visit invitation saves the visit; the separately labelled undo action delegates to the existing exact-visit safety check. Theme switching moved to Settings and still uses the same persisted state operation. No schema, state mutation or storage adapter changes were required.

The Session 2 wizard delegates saving to the same atomic state operation and retains its repeated-submission guard. Search displays at most six suggestions or twelve matching tags; selected tags remain independently removable. Category inputs show descriptions rather than internal integer scores. Local validation retains the existing ten-tag/thirty-character limits, reveals unfinished custom input on save and rejects duplicate custom tags. No database or ownership behavior changed.

Session 3 presents the same derived collection and rankings through independent catalogue/diary tabs and compact metric controls. The diary groups UTC-stored timestamps by their local calendar date and displays scores only on reviewed visits, including explicit zero. Profile statistics use unique discoveries, all personal visits/reviews and independent favourites; navigation reuses the diary and existing bathroom cards rather than embedding histories on the profile. No state mutations, ranking formulas, schema or storage behavior changed.

## Session 4A experiences and visual identity

`BathroomIdentity`, `CategoryLabel` and `ReviewTag` are reusable presentation components for later destinations. Stored tag text is never rewritten: recognized legacy labels gain a separate emoji avatar, unknown labels a neutral tag icon, and already decorated labels retain their single original prefix. Summary continues to distinguish community arithmetic averages from the latest personal reviewed visit.

`ExperienceDetailsPage(visitId: ...)` represents exactly one visit, never an overall bathroom summary. It resolves current state on rebuild and displays bathroom identity, visit date, optional review/global score, original category descriptions and tags. Own visits expose optional review creation/editing and confirmed removal (including the associated-review warning); other users' visits expose no mutation actions. Personal history rows navigate here and expose a compact contextual menu. Reviewed rows prioritize the experience emoji, score and details; standalone rows say Visita registada with a neutral icon and secondary date. Session 4B will connect the collection diary to this same route.

New installations seed deterministic fictional demonstration data with discovered/undiscovered bathrooms, reviewed/unreviewed visits and a favourite. Existing databases are not reseeded. See the experimental storage policy before any future incompatible upgrade; it must be replaced before real users or production data.

## Session 4A verification

Verified locally on 2026-11-25: all 89 tests pass, including v2 migration/relational/settings preservation, selected identity persistence/restoration, legacy tag text, explicit visit associations, atomic new review/cancellation/zero/duplicate handling, history navigation, ownership, editing, confirmed removal and undo. Formatting and strict analysis pass (only the exact documented Material-import baseline, now 26 files). Linux and Android debug builds pass. Layout checks cover 320/390/1200 px in both themes with enlarged text, alongside existing accessibility checks. Flutter-rendered Explore, details, experience and creation captures were inspected in light/dark themes with loaded text, icon and emoji fonts. Android system-back routing is covered through Flutter's route-pop handling; physical phone acceptance of Session 4A remains open. Hosted CI is reported after push without waiting. Session 4B and backend development have not started.

## Session 4D — Structured review content (supersedes earlier tag/input descriptions)

`Review.tags` is an immutable list of `ReviewTagData` values with separate `emoji` and `label` strings. The constructor accepts legacy strings at the compatibility boundary; application drafts and SQLite v4 use structured values. `TagPresentation` and `ReviewTagData` are the canonical presentation, conversion and equivalence implementation. Recognized legacy prefixes and meanings survive conversion; unknown undecorated tags receive 🏷️. Labels trim/collapse whitespace, compare case-insensitively and retain the grafiti/graffiti alias. Emoji differences never create distinct label identities. Limits remain ten selected tags and thirty label characters, counted as extended graphemes consistently with Flutter text input. One emoji can contain multiple codepoints, including modifiers, ZWJ families, flags and keycaps.

`Review.comment` is optional plain text, trimmed on construction; blank input becomes null. The 500-character limit counts extended graphemes. Comments have no effect on scores, rankings or statistics. Editing retains review identity, ownership and visit association. The third wizard step is **Etiquetas e comentário** (compact indicator: Etiquetas); both inputs are optional. Its controllers retain drafts across navigation and comment changes participate in discard detection. Individual experiences display the complete comment; community entries show up to four lines and link to the full experience.

Overall input is an explicit horizontal 0–5 slider in tenths, beneath decorative golden fractional stars, the decimal score and reactive emoji. Unanswered stays null until interaction, including an explicit minimum interaction; editing restores the saved rating. Detailed scales remain discrete. Custom tag creation stays behind the existing capability flag and offers suggested emojis, a system-keyboard emoji field, separate label, live preview and explicit confirmation.

A future shared catalogue could map these local values to separately identified catalogue records while retaining review snapshots. Remote identity, community permissions and equivalence enforcement require backend evaluation; no catalogue, remote IDs, reputation, moderation or power-ups are implemented. Shared comments will need moderation, reporting and privacy policies before publication. Bathroom categorization remains exploratory and the public catalogue/contribution direction is unchanged.


## Phase 2.2A — Persistence and provenance

The local repository commits validated actions before observable state changes. Direct review creation and confirmed visit/review removal are SQLite transactions. Notifications and derived queries never write. A failed action retains its exact input separately from committed state until explicit retry succeeds; pending input is lost if the process exits before retry. No visible workflow, rating description, ranking formula or Portuguese text changes.

SQLite v5 stores provenance independently of attribution on bathrooms, visits, reviews and favourites: `demo`, `unclassified_legacy`, `user_created`, `remote`. The distributed v4 database upgrades transactionally without content loss. Stable sample bathroom IDs `0`–`5` and their existing and future related records remain demo, including edited samples and newly generated UUIDs. Other pre-existing prototype rows conservatively remain unclassified. New genuine local bathrooms are user-created; new visits/favourites inherit their bathroom restriction and reviews inherit their visit restriction. New locally authored children of a future remote catalogue entry are user-created. Editing preserves origin. No remote import exists yet.

Demo and unclassified legacy never pass the necessary `allowsFutureUpload` gate; remote cache records also do not represent local contributions. User-created provenance alone does not authorize synchronization or publication. All records remain locally visible and functional. Provenance is an accidental-upload safeguard, not authentication or server-side evidence of truth. No account association or bulk import is implemented. The guest application remains local-only; Phase 2.2B adds an explicitly configured test foundation below. See [storage](storage.md) for failure semantics, migration and verification. Earlier snapshot/schema descriptions in this document are historical.

## Phase 2.2B — Scoped identity and protocol metadata

Domain entities remain separate and retain all existing identity/relationship/rating/time/tag/comment rules. v6 adds a scope binding per SQLite file: local guest, stable auth subject plus backend environment, or environment-shared public catalogue. Existing v5 entities and settings remain unchanged in the guest. Account stores use their subject as the local mutation actor, never an email or automatic remapping of `local-user`. The actual AppState bootstrap is still guest-only.

Eligible test mutations commit immutable outbox commands with UUID operation identities, entity IDs/types, scope, dependencies, base revisions and retry state. A direct review is one atomic visit/review command; favourites set explicit booleans. Provenance restrictions survive edits and deletions; fixture/cache/theme/read/notification paths do not queue. There is no production association or publication policy.

Server revision metadata, canonical remote snapshots/tombstones and opaque scoped checkpoints are separate from local domain drafts. Conflicts retain the submitted review and remote revision/content for future explicit resolution. Pull refreshes never replace local pending edits or resurrect tombstoned identities; cache snapshots are not currently materialized into UI/rankings. Public and private cache/checkpoint files remain separate. See [client synchronization](backend/client-synchronization.md) for the actual invariants and deferred server requirements.


## Phase 2.2C — Server authority without application rollout

The server derives ownership from Auth, retains immutable associations and relational constraints, and uses revisions for CAS rather than device dates. Review changes advance the parent visit revision; atomic compound creation/deletion acknowledges both entities consistently. Favourite commands set desired booleans. Sync bathroom submissions remain pending proposals and reviews remain private; synchronization cannot approve or publish content. Private state and public allowlisted projections use independent feeds, including visibility removals and terminal tombstones. Local drafts, UI, rating descriptions, rankings and grapheme validation are unchanged. See [server synchronization](backend/server-synchronization.md) for the exact remaining codepoint/grapheme integration gate and deferred product decisions.


## Phase 2.3A — Optional account foundation

The normal application still restores the local guest and fictional examples. Only an explicit test context restores account AppState from its `(environment, stable authenticated subject)` file, with empty first-run content and the subject as mutation actor. Email never keys ownership. No guest owner mapping, sample copy, public profile or remote-cache view composition is implemented. Existing entity/review/visit distinctions, provenance, Portuguese workflows, ratings and rankings are unchanged.

Authentication is observable identity/session lifetime, separate from consent to associate/upload private data or publish content. Test account repositories omit outbox authorization by default; existing atomic queueing requires its separate explicit fixture capability. Open editors and failed local commits block test selection/disposal, and session loss retains their original state in memory. Committed original-account work survives restart. See [offline account integration](backend/offline-accounts.md) for lifetime, validation/conflict recovery and remaining production policies.
