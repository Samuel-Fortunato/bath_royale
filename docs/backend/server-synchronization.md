# Server synchronization protocol — Phase 2.2C

Current application integration: [A2 private account synchronization](private-account-synchronization.md). A1.1 UX is owner-accepted; A2 enables explicit-consent private synchronization and recovery without guest association/public identity. Test-only/disabled statements below describe the historical foundation milestone, not the current configured app.


Phase 2.3B adds optional production authentication and approved offline device lifecycle; see [production authentication](production-authentication.md). Earlier guest-only/test-only descriptions below are historical foundation details. Domain synchronization, association and public-profile creation remain disabled.

This protocol is implemented by ordered migration `202611260002_synchronization.sql`, on top of the unchanged Phase 2.1A schema. `HttpRemoteDataSource.forTesting` exercises it through the isolated local Auth/PostgREST APIs. The ordinary Flutter bootstrap remains guest-only. Nothing opens an account database, associates guest history, uploads the existing SQLite file, stores production credentials or enables account UI. Phase 2.3 has not started.

## Disposable verification environment

Use the existing locked backend shell and rootless lifecycle:

```sh
POC_INSTANCE=sync nix develop .#backend --offline --no-write-lock-file --command python3 backend/synchronization.py
POC_INSTANCE=sync nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py status
```

The runner requires `POC_INSTANCE=sync` and refuses every other installation. It starts `bath-royale-poc-sync`, generates independent passwords/JWT signing material, uses its own `-db-data`/`-db-config` volumes and `-network`, and publishes only `127.0.0.1:55461` (Auth) and `127.0.0.1:55462` (PostgREST). PostgreSQL has no host listener. It uses the existing image digests, Nix lock and rootless checks. A port collision fails startup. Private state is `$XDG_STATE_HOME/bath-royale-poc-sync` (default `~/.local/state/bath-royale-poc-sync`); credentials never enter Git or SQLite.

The authorization suite intentionally resets only this installation's fictional fixtures. Each transport run adds a fresh fictional approved catalogue entry and uses independent A/B logins. A mode-0600 temporary test configuration passes short-lived sessions to Flutter and is removed afterwards. Separate Dart fixture processes use it without saving credentials. The runner stops the installation in `finally` after verification, retaining credentials, volumes and network. `--skip-authorization` is an iteration aid; final acceptance runs the complete matrix, including actual JWT expiry. No managed project or any of the three preserved migration installations is contacted, inspected or changed.

## Submit contract

Authenticated `POST /rpc/sync_submit`, with the actual Auth access JWT in the Bearer header:

```json
{
  "command": {
    "operationId": "<UUID>",
    "entityType": "review",
    "entityId": "<review UUID>",
    "type": "createVisitReview",
    "payload": {"visit": "<SQLite row object>", "review": "<SQLite row object>"},
    "baseRevision": null,
    "dependencies": {"<acknowledged predecessor operation UUID>": 12}
  }
}
```

The angle-bracket values above describe types, not literal values. Operations use the exact immutable v6 outbox snapshots, without altering queued rows on retry:

| Command / entity | Payload |
| --- | --- |
| `createBathroom`, `updateBathroom` / `bathroom` | SQLite bathroom row: `id,name,normalized_name,creator,emoji,accent,provenance` |
| `createVisit` / `visit` | SQLite visit row: `id,bathroom,user,at,provenance` |
| `createReview`, `updateReview` / `review` | `{review: <SQLite review row>}` |
| `createVisitReview` / `review` | `{visit: <SQLite visit row>, review: <SQLite review row>}` |
| `deleteVisit` / `visit` | `{id,deletedReviewId}`; child ID is null for an unreviewed visit |
| `setFavourite` / `favourite` | `{user,bathroom,value}`; `entityId` is the bathroom UUID; `value` is a JSON boolean |

Review row fields are `id,visit,bathroom,author,created,updated,rating,paper,hygiene,comfort,aesthetics,tags,comment,provenance`. `tags` is the SQLite JSON **string** containing emoji/label objects. The server derives version-1 canonical keys (including grafiti → graffiti), then applies the existing tag constraints. `at` is UTC microseconds since epoch. Device review `created`/`updated`, normalized names and provenance are snapshot metadata, not remote authority: server creation/update timestamps remain server-derived, and device dates never arbitrate conflicts. Unknown fields are rejected, including approval/publication/ownership overrides. IDs must be UUIDs and the payload's identity must match its envelope.

Successful HTTP 200:

```json
{"subject":"<authenticated subject UUID>","status":"acknowledged","revision":13,"entities":[
  {"entityType":"visit","entityId":"<UUID>","revision":13,"deleted":false},
  {"entityType":"review","entityId":"<UUID>","revision":13,"deleted":false}
]}
```

A command's transaction has one server revision for **all** affected entities. Creating or editing a review also advances its visit's revision, preventing a deletion confirmed against an older review from removing newer content. Compound creation acknowledges both identities at that same revision; compound deletion acknowledges both terminal tombstones. The existing `Future<int>` transport contract remains sufficient. The real adapter verifies target coverage and equal revisions in `entities`; the SQLite acknowledgment transaction advances the review and referenced visit together. Existing fake transport/local behaviors remain covered.

## Ownership and authorization

`auth.uid()` and an existing matching profile are required. Each payload actor must equal that subject, but database ownership is always written from the authenticated subject. Email, editable JWT metadata, provenance claims and UUID knowledge grant no rights. Receipts, private records, cursors and feeds are subject-scoped; no API parameter chooses a private account.

The definer entry points have empty fixed search paths, fully qualified objects, explicit subject checks and narrow execution grants. Submit is authenticated-only; pull grants anonymous execution solely for its public branch. Internal helpers, log tables, receipts, counters and sequences have no client execution/data grants. Existing table RLS, column grants, immutable triggers, relational constraints and moderator checks remain intact. Original table writes also pass through synchronization capture/locking triggers; their revisions cannot become invisible to CAS clients.

Only a contributor's **pending** bathroom can be updated through synchronization. Creation always inserts a pending, unverified contribution. Visits/favourites require an approved bathroom, including when a predecessor receipt exists for its pending proposal. A receipt cannot confer moderation rights. Reviews require the same owner/bathroom as their visit; associations stay immutable and one review per visit remains enforced. Sync commands never set `published`, approve proposals or edit moderation metadata. The existing separately authorized publication/moderator paths retain their prior restrictions.

Client provenance is only an accidental-upload safeguard. A malicious client can claim any provenance; the server cannot prove that its content is genuine. The real suite explicitly demonstrates this boundary while checking that the actual repository excludes demo/unclassified records from upload.

## Receipts and dependencies

`app_private.sync_receipts` is keyed by `(authenticated subject, operation UUID)`. It retains the complete canonical JSONB request as a collision-free immutable fingerprint and its resulting outcome. Object key ordering is irrelevant; payload strings (including serialized tags), dependency maps, base revision, operation type and IDs are bound. No client timestamp or local attempt counter participates.

The command takes a transaction-held writer lock before receipt lookup. Concurrent duplicate requests therefore observe the first committed receipt. Identical committed retries return the original result, including an original conflict. Changed content under that operation ID fails with SQLSTATE `22023`/HTTP 400. Domain changes, change feed entries, revisions and receipt insertion commit or roll back together. Constraint/auth/validation errors leave no success receipt. Response loss after commit is safe to retry; a failed local acknowledgment also retries the same ID. There is no partial durable “success” placeholder.

Each dependency must be an existing **acknowledged** receipt owned by the subject, with exactly the supplied revision. Rejected/conflicted/nonexistent/foreign dependencies fail. The server considers a predecessor revision as a causal base only if its `entities` acknowledges this exact entity. This permits edits queued with a null/older base before their create/edit predecessor completed. Unrelated receipts do not advance that base, and another device's intervening write still conflicts. Domain ownership, existence, associations and publication eligibility are checked independently of dependency receipts.

## Conflicts, deletion and drafts

CAS compares the effective base revision against server state. It does not use device dates. A stale command returns HTTP 200 with a durable structured conflict:

```json
{"subject":"<authenticated subject UUID>","status":"conflict","conflict":{
  "entityType":"review","entityId":"<UUID>","revision":14,
  "deleted":false,"payload":{"comment":"Current authorized remote content"}
}}
```

Payloads are full current authorized server rows, or `{}` with `deleted:true` for a terminal removal. Another account's private content is never returned. A nonexistent/unauthorized identity is a rejection rather than a disclosure. The client stores conflicts separately and retains local domain drafts and exact outbox payloads; there is no merging or resolution UI.

`deleteVisit` verifies its confirmed child ID and the visit revision, which incorporates child changes. The visit and its optional review delete in one PostgreSQL transaction through the existing cascading relationship. A stale delete conflicts; a stale edit/create against a removed identity returns its tombstone and cannot resurrect it. A private trigger also blocks reuse of terminal bathroom/visit/review IDs through ordinary insert paths. Tombstones are retained even after physical row removal.

Favourites express desired booleans with CAS, never toggles. Deleting a favourite emits `value:false` as a nonterminal state; setting true again remains possible. Even false on an absent row records the desired state and a receipt.

Public visibility withdrawal emits `deleted:true,payload:{"_visibility":false}`. This is a cache removal, not an identity tombstone: a later higher-revision approved/published projection can return. Actual row deletions have an empty terminal payload and cannot return. SQLite recognizes only the explicit visibility marker as reversible; terminal tombstones still reject all later upserts. Never-public proposals and private reviews are not emitted as new public identifiers merely because they were deleted.

## Pull contract and committed checkpoint correctness

`POST /rpc/sync_pull` accepts `{feed:"private"|"catalogue",checkpoint:null|"<opaque UUID>",page_size:1..100}` and returns `{subject:"<authenticated UUID>"|null,changes:[<RemoteChange>],checkpoint:"<opaque UUID>",reset:false|true}`. Each change has `entityType,entityId,revision,deleted,payload`. An empty page still supplies a checkpoint. The client treats the checkpoint as opaque and atomically applies the whole bounded page, revision metadata, removals, retry clearing and checkpoint in SQLite. An injected checkpoint failure rolls back the cache too.

Private pull requires Auth and returns only that account's proposal/history/review/favourite changes. Public pull needs no Auth and contains only bathroom and published-review projections. Bathroom public fields are `id,name,emoji,accent,institution,locality`; review fields match the existing exact `public_reviews()` allowlist. No private visits, visit IDs, exact visit timestamps, favourites, account emails or record timestamps enter that feed. Bathroom visibility changes also remove/restore affected published reviews. Public username edits update visible review projections. The public sentinel scope is distinct from every private account; supplied foreign-feed/account cursor UUIDs fail identically to unknown cursors.

Every domain-changing statement acquires the same singleton clock row **before** it acquires domain row locks. The lock survives until transaction commit/rollback. Under that lock, the transaction allocates one revision and capture triggers allocate log positions. Subsequent writers cannot allocate a log position until that transaction finishes. Rollbacks remove their rows; gaps are harmless. Consequently, after position N is visible, no smaller position can commit later. A pull statement sees a committed snapshot, sorts by position, and records exactly its last returned position. It never advances to an independently allocated sequence value. Multiple changes within one transaction use distinct positions under the same revision; repeated changes to one identity in that transaction coalesce to its final snapshot.

The log position uses an identity sequence **inside this transaction-held lock**, not a naked pre-commit sequence as a synchronization watermark. The overlap test first allocates candidate sequence values/transaction IDs in A then B, commits B first, paginates it, then commits A and verifies its later page. A separate test observes B actually waiting on the database lock after A allocated a synchronization revision; B cannot publish a later watermark first. This covers both reverse candidate commit ordering and the invariant that prevents reverse watermark commit ordering. Coarse serialization is an intentional throughput limitation for this prototype.

Cursors expire after seven days in this test protocol. An expired **known, correctly scoped** cursor returns `reset:true` and starts bounded replay from the beginning. Unknown or mismatched cursors are rejected, not treated as another account's initial cursor. For a lost cursor, explicitly request `checkpoint:null`. The current append-only log retains all initial snapshots and subsequent changes, so full replay reconstructs the cache without clearing local domain tables, outboxes, conflicts or drafts. Existing higher revisions and terminal tombstones remain safe during replay. This makes expiry safe without deciding any production compaction/tombstone retention policy. Pruning the log would require a new snapshot/epoch protocol first.

## Transport errors

| Result | Client classification |
| --- | --- |
| HTTP 200 acknowledged | Verify shared revision/target coverage, then acknowledge atomically |
| HTTP 200 conflict | Structured `RemoteFailureKind.conflict`; preserve draft and remote state |
| HTTP 401, missing token | `unavailableAuthentication`; pause this session generation |
| HTTP 403 | `authorization`; reject operation/block pull |
| Other HTTP 4xx, including 400/409 constraints or changed-ID requests | `validation`; no automatic command retry |
| HTTP 429/5xx, socket/HTTP I/O error, 15-second request/read timeout | `transport`; durable bounded retry/backoff |
| Malformed success or inconsistent acknowledgment | Propagate programming/protocol error; no local success acknowledgment |

After awaits, the coordinator validates generation, namespace and expiry before any acknowledgment or cache application. Switching away and back invalidates the original response. Already committed server work remains under its original account and retries by the same operation UUID after reauthentication. The adapter also rejects a namespace outside its configured environment before sending. Every private response echoes the server-derived subject, which must match the requested namespace before the adapter returns data. A deliberately mismatched A-context/B-token request is rejected even if a test token provider is misbound. Tokens are supplied in memory by the explicit test configuration; there is no production SDK/session implementation.

## Unicode compatibility gate and deferred decisions

Existing Flutter semantics stay unchanged: bathroom input limits, thirty-grapheme tag labels, single-grapheme emoji input and 500-grapheme comments use extended graphemes. PostgreSQL still enforces the existing codepoint bounds: bathroom name 1–100, labels 1–30, comments 1–500, and the conservative emoji subset with at most 16 codepoints. For example, 251 copies of `e` plus combining acute accent are 251 Flutter graphemes but 502 PostgreSQL codepoints, so a locally valid draft is rejected remotely. Sixteen such label graphemes already exceed the server's thirty-codepoint bound. Long valid emoji clusters may exceed the subset/16-codepoint bound. The real matrix and synchronization rollback tests exercise this mismatch.

**Remaining integration gate before enabling account synchronization:** implement and test equivalent Unicode segmentation on the server, or obtain an explicit product decision for a separately explained remote bound and recoverable validation UX. Do not truncate, normalize away content, silently tighten the wizard or declare codepoints equivalent to graphemes. Today validation rejection retains the local draft and rejected operation; no account UI exposes this unfinished path.

Private-history backup consent, guest association, production authentication/credential storage, account-switch/device-removal policy, public review metadata, moderation, retention/compaction, account erasure and conflict resolution remain deferred. No production tombstone retention or erasure policy is selected. This coarse lock, unpruned log/receipts/cursors and private test state require operational review before real users. The earlier migration export allowlists/evidence describe the older schema: future portability rehearsals must explicitly include the new synchronization metadata or define a safe new epoch; this milestone does not rerun them. No background services, Realtime, paid services, packages or global NixOS configuration changes are added.

## Executed evidence

Final check counts and build results are recorded in [ROADMAP.md](../../ROADMAP.md). The version-controlled real suite covers actual Auth/API requests and database transactions, concurrent duplicates, immutable receipts, causal dependencies, atomic compound rollback/acknowledgments, conflicts, tombstones, reverse candidate commits and locked watermark allocation. Seven real Flutter tests cover separate processes with committed pending work, commit without local acknowledgment, offline compound/queued edits, favourite retry, two devices/delete races, actual expired JWTs, account-switch response invalidation, environment rejection, cache/checkpoint rollback and client provenance exclusion. The existing authorization matrix is repeated on the new schema; the original 142 Flutter regressions remain intact alongside focused acknowledgment/visibility regressions.


Final executed run on 2026-11-26, after a clean rebuild of **only** the disposable sync installation: **232 authorization/authentication assertions**, **154 server protocol assertions** and **7 real Flutter integration tests** passed. The ordinary Flutter run passed **144 tests**, retaining all original 142 and adding two focused regressions; its real-suite placeholder was intentionally skipped because the actual seven tests ran through the private configured runner. All **25 offline backend tests** passed, including the isolated PostgreSQL fixture. Dart formatting, strict analysis with the exact unchanged Material-import baseline, Ruff lint/format and Linux/Android debug builds passed. Documentation link checks passed. The final runner stopped all three sync containers and retained its volumes/network/private credentials; no migration installation or managed project was accessed.

Earlier iteration failures were corrected: a fixture reused an already-favourited server entry without its revision, a Dart import was unnecessary, and PYTHONPATH had to be set inside the Nix shell. Privacy review then caught/remedied removal events for never-public proposal IDs and added a regression before the final clean run. Subject echo validation and a mismatched-token regression were also included in the final successful run. No failed or unexecuted check is counted as passing.
