# Client synchronization foundation (Phase 2.2B, extended by 2.2C)

The foundation was implemented against `dd317f8` and completed at `e0d620a`. Phase 2.2C adds the [server protocol and real local transport verification](server-synchronization.md); the earlier fake-only descriptions below are historical where superseded. There is no production authentication UI or cloud project connection. The application still opens only the guest repository. `SyncWriteContext.forTesting` is an explicit opt-in at repository construction in tests, not a publication or guest-association policy. No managed project or preserved backend installation is used by these tests.

## Scope and boundaries

`DataNamespace` identifies guest, `(environment, stable subject ID)` account and `(environment)` public catalogue scopes. Environment identifiers must be stable deployment identities, not display labels. The guest file keeps its original `bath_royale.sqlite` path. Other file names derive deterministically from UUID v5 of the complete encoded scope; a checked singleton inside each database verifies the exact scope on every open. A collision or incorrectly supplied file fails closed. Email is never an identity key. Files provide logical isolation within the application's private directory, not encryption against the operating-system user.

Every file has the same schema. Guest data, account domain rows, outboxes, revisions, conflicts, retries and cache records never share a database. Public catalogue caches are shared across accounts only within the same environment; they accept only the catalogue feed. Account caches accept only the private feed. The guest accepts neither. The existing AppState bootstrap explicitly rejects non-guest stores: account/public view composition and session UI are future integration work. Fresh account/public stores initialize empty; only guest bootstrap seeds fictional examples. Opening a namespace never copies another file or associates guest rows with an account.

`BathroomRepository` retains targeted domain transactions. An explicitly configured test context must match an account store. Mutation actors must match its subject. `SyncStore` persists protocol state on that same connection; operation completion methods also reject mismatched scopes or input. `AuthSession` exposes immutable scope/expiry and a generation changed on every renewal, switch or logout. `RemoteDataSource` has submit and bounded pull methods; it has a deterministic fake and, in 2.2C, an explicitly injected local HTTP test adapter. No new packages, background services, Realtime or generic synchronization framework are added.

## Durable mutations and ordering

The v6 migration only adds tables. All v5 entity columns/IDs, relations, provenance, timestamp precision, tag JSON, comments and settings remain untouched in the guest file. Migrations, namespace binding and foreign-key validation are one rollback-capable transaction. Existing data cannot be opened as an account, even during upgrade. Future/corrupt/mismatched files fail without deletion.

Eligible repository writes insert the domain mutation and a UUID v4 outbox operation in one transaction. An operation stores entity/type/command, immutable JSON snapshot, exact scope, base server revision, ordered sequence, dependency edges, status, attempts, next due time and error category. Parent operations and previous unacknowledged operations on the same entity become dependencies. Rejected/conflicted predecessors block descendants. Ready operations include acknowledged predecessor IDs/revisions for the future server protocol. Receipts are retained; no pruning policy is decided here.

Direct review creation uses one `createVisitReview` command containing both visit and review. Deletion carries the related review ID and atomically removes both domain rows and records tombstones. Favourites carry explicit true/false values. Local ordering, ownership, relational checks and UI confirmation behavior remain unchanged.

Provenance is necessary but insufficient authorization. Demo and unclassified rows, including inherited children and existing unclassified favourites, are excluded. Remote cache application does not enqueue; locally authored children of a remote bathroom can be eligible only in the explicitly opted-in account test context. Guest actions, fixture initialization, theme, reads and notifications never enqueue. No automatic history association, import or application upload exists.

## Execution, errors and retry

One execution runs per AuthSession within this process, including across scoped coordinator instances. Each invocation attempts at most the configured operation batch (default 20, allowed 1–100) and one bounded pull page. The caller invokes execution explicitly; there is no scheduler or timer. Dependencies must be durably acknowledged before submission. Submit snapshots, operation IDs and predecessor receipts remain unchanged across retries/restarts.

After every await, account work checks generation, scope and expiry before acknowledging, recording errors or applying pull results. Switch-away-and-back also invalidates a response. A request already sent cannot be recalled; its original account may have committed it. Its original outbox entry stays pending, and reauthentication retries the same operation ID against server deduplication. No request is replayed under another subject/environment.

| Result | Local behavior |
| --- | --- |
| Acknowledgment | Transactionally mark acknowledged and advance server revision metadata; domain draft remains intact. |
| Transport/temporary service failure | Persist attempts, error and next due time; stop this execution. Retry on a later invocation when due. |
| Missing/expired session | Send nothing; local use and committed queue survive. |
| Remote authentication unavailable | Pause the current generation until a session change; no operation is discarded. |
| Authorization/validation rejection | Persist rejected state; do not retry automatically; dependents remain blocked. |
| Revision conflict | Persist conflict plus remote revision/payload, retain original command and local review/visit content; no automatic resolution or new UI. |
| Local SQL/unknown programming failure | Propagate; rollback the affected transaction and retain prior durable state. |

Transport delay is uniformly jittered within 50–100% of `min(300000 ms, 1000 ms × 2^attempts)` by default. Clock and jitter are injectable; the exponential and exponent are bounded. Pull transport errors have their own durable per-feed retry state. Permanent pull rejection blocks the feed until explicit `retryPull`; successful page application clears retry state atomically. Authentication pauses/execution locks are memory-only; after restart session validity is checked again. No credentials persist here.

## Revisions, cache and checkpoints

Server revision numbers, not device dates, govern stale-record checks and conflict metadata. Acknowledged revision metadata is separate from canonical cached payloads so an acknowledgment cannot hide an equal-revision pull. The local domain tables/outbox are also separate from `remote_records`, so refreshing canonical cache never overwrites unsent text, scores, relationships or deletions. Cache-to-UI composition is deferred; this milestone does not display remote reviews or change local ranking inputs.

Each pulled page, revision update, tombstone and opaque checkpoint commits in one transaction. Failed application/advancement retries from the old checkpoint. Private and public checkpoints reside in different scope-bound files; their feed names cannot be interchanged. Non-increasing revisions do not overwrite existing cache snapshots. Once terminally tombstoned, an entity cannot be revived by an upsert, even at a higher revision. Phase 2.2C adds an explicitly reversible public visibility-removal marker, distinct from terminal deletion. Explicit restoration, tombstone retention/compaction and full-refresh expiry policy remain future protocol/product decisions.

Durable after commit: domain mutations, eligible outbox payloads/IDs/dependencies, receipts, retries, rejections/conflicts, deletions, canonical cache and checkpoints. Memory-only: unsaved wizard fields, a failed pre-commit AppState action and its completion callback, execution lock and current session generation/pause. Failed local commits still use the existing blocking retry screen; killing the process before commit loses that input. Committed pending operations survive process loss, including loss between server success and local acknowledgment.

## Original requirements for Phase 2.2C (now implemented separately)

The fake records `(scope, operation ID)` plus immutable request fingerprint and result; it can simulate commit followed by lost response. This proves client retry behavior only. The server still needs authenticated ownership derived from the session, payload fingerprint checks, durable idempotency receipts, transactional visit/review commands, final relationship/validation constraints, compare-and-set revisions, tombstones and privacy-safe public projections. It must define command revisions for compound operations and verify acknowledged predecessor receipts when edits were queued before their predecessor completed; a client base revision alone cannot solve that causal case. Conflicting writes must return the current remote revision/content rather than use client timestamps.

The bounded pull interface/checkpoints do **not** solve committed watermarks or pagination gaps. Phase 2.2C must prove overlapping transactions/late commits cannot be skipped, define cursor expiry/reconciliation, and verify real crash/retry and scope isolation end to end. No server commands are implemented here. Private-history backup, account association, publication metadata, moderation, erasure and production authentication remain unapproved.


## Phase 2.2C protocol alignment

The [implemented protocol](server-synchronization.md) binds authenticated receipts to complete immutable requests, validates predecessor entity acknowledgments, shares one server revision across all affected entities and serializes change allocation through commit. The `Future<int>` submission contract is retained; real responses additionally enumerate affected identities, which the adapter validates. Review creation/edit acknowledgment now advances its referenced visit as well, matching the server's deletion-conflict guard. Public visibility withdrawals carry an explicitly reversible cache marker; physical deletions remain terminal. Favourite false states are nonterminal desired states.

Expired known cursors safely start bounded full-log replay; downloaded pages and checkpoint changes still commit atomically without clearing drafts. The production opener remains guest-only. The test-only HTTP adapter, separate-process fixtures, seven real Flutter integration tests and server attack/overlap tests supply evidence beyond the deterministic fake. Unicode equivalence, production auth/publication/backup/retention/erasure and cache-to-UI composition remain explicit gates in the server document. No Phase 2.3 work is enabled.
