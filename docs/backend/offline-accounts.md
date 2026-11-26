# Offline account integration foundation — Phase 2.3A

Phase 2.3B adds optional production authentication and approved offline device lifecycle; see [production authentication](production-authentication.md). Earlier guest-only/test-only descriptions below are historical foundation details. Domain synchronization, association and public-profile creation remain disabled.

Production bootstrap remains `StorageBootstrap` → `AppState.restore` → guest SQLite → Provider. It neither constructs an authentication adapter nor opens an account/cache file, creates an outbox context, schedules synchronization or needs a backend. Existing Portuguese UI, samples, review workflows, ratings and rankings remain unchanged. No login or production account selector is introduced. No authentication SDK or credential package is installed.

## Session identity and lifetime

`AuthSession` is now a `Listenable` identity boundary with unauthenticated, authenticated, expired and invalidated states. `SessionIdentity` still carries only the `(backend environment, stable authenticated subject)` namespace and expiry in epoch milliseconds, never email or credentials. The existing coordinator re-exports these types so existing clients retain their imports. The remote submit/pull contracts, HTTP transport and server schema/protocol are unchanged.

The injected `FakeAuthSession` is memory-only. Switching, logout, invalidation, successful renewal and explicit expiry events advance its generation and notify listeners. Its injected clock reports expiry even before `checkExpiry()` emits an event. A future real adapter must deliver expiry/resume events; no timer/background service is introduced here. Renewal retains the exact namespace and requires a future expiry. A renewal response from an older generation, including after disposal, cannot restore a session or switch accounts. Renewal failure leaves the current identity intact; expiry still prevents requests.

The coordinator checks generation, exact namespace, expiry and connection lifetime after asynchronous operations. Switching away and back, renewing or retiring a store invalidates delayed acknowledgment/pull results. Already submitted work may have committed remotely; the original account's committed operation remains durable and retries with its original ID. Session validity never proves synchronization consent.

## Explicit test-only application lifecycle

`AccountStateScope.forTesting` owns one selected `AppState`, repository and namespace-bound SQLite connection. Its opener and clock are injected. `select` requires a matching unexpired session for account stores and rejects public caches as mutation state. It initializes accounts through `AppState.restoreAccountForTesting` with explicit empty lists, subject ownership and an initialization marker. Account constructors also reject implicit guest sample defaults. Subsequent opens restore committed content/settings without reseeding. The guest initializer, original guest path and migration policy are unchanged.

Identity events alone never select or open a store. Selection does not copy guest records, remap `local-user`, join databases or read another account/environment. A/B subjects and environments retain separate files under the existing v6 namespace binding. Failed opens retain the selected state; delayed opens are closed if a newer selection, session generation or disposal overtakes them. Successful selection disposes the old state/connection; stale references cannot mutate disposed state. `LocalStore.close` is idempotent and exposes lifetime to the coordinator.

`AccountStateProvider.forTesting` borrows the scope through Provider `.value`; the caller owns scope disposal. A successful replacement keys/remounts the complete subtree, including Navigator routes, removing old Provider listeners and widget state. Expiry, invalidation, logout or a foreign identity hides the account subtree and excludes focus while retaining it in memory. Matching renewed authentication restores that same tree. No other account is automatically displayed. Clock events must be emitted by the injected adapter to rebuild the view; request/selection checks independently validate expiry.

Open review and bathroom editors retain an idempotent draft lease on their original AppState until disposed. This conservatively includes pristine editors. Selection and scope disposal reject while any editor is open or a local action has failed before commit. If authentication changes meanwhile, the hidden editor and original state remain retained; reauthentication restores the editor. The original retained state can retry a failed transaction without assigning it to the new identity. Explicitly finishing/cancelling the editor and retrying the commit releases the barrier. Checks are repeated after store-open awaits so a newly opened editor cannot be discarded by an in-flight selection.

This is a verification harness, **not an approved production logout, account-selection, offline-account-access or device-data retention policy**. Its retained `state` reference belongs to the test owner for recovery, not to a new account's view. There is no production discard, delete-on-logout, multi-account browser or retention UI. Unmount the test Provider subtree before disposing its owner. Normal application teardown and process death cannot make unsaved drafts durable.

## Identity is not transfer authorization

The default account repository has no `SyncWriteContext`. Authentication, account selection, ordinary actions, notifications and renewal do not create one or execute a coordinator. An explicit `synchronizationForTesting` argument is a separate fixture capability, never inferred from authentication and never a production consent record.

Consequently identity alone does not associate guest data, upload private history/favourites, publish reviews, create public profiles or transfer demo/unclassified legacy content. Existing provenance restrictions remain necessary but insufficient authorization. When tests explicitly enable queueing, domain writes and exact outbox snapshots still commit atomically; a failed transaction changes neither. No existing sample or legacy origin is promoted.

Durable: committed domain/settings, original-account pending operation IDs/payloads/dependencies, receipts, retries, conflicts, cache and checkpoints. Memory-only: session identity/generation, open editor controllers, draft leases and failed pre-commit actions/completion callbacks. Switching/logout does not delete committed pending work. Process termination before commit can still lose input, as the existing storage retry screen explains.

## Minimum production requirements — subsequent milestones only

| Boundary | Gate before enabling production |
| --- | --- |
| Real authentication adapter | Approve the authentication method and email delivery/confirmation/recovery requirements. Verify subject/environment binding, session events, renewal concurrency, expiry/resume, revocation and offline behavior; never infer identity from email. Wire credentials to the existing transport only for the matching current generation. |
| Secure credential persistence | Select and verify platform-backed protected storage on Android and Linux, including locked/unavailable key-store behavior, refresh-token rotation, restart/recovery, backup exposure, redacted logs and credential removal. SQLite namespaces are neither encryption nor credential storage. No plaintext/file fallback or package is selected here. |
| Selection/logout/device data | Approve account selection, guest return, offline account access, local retention/removal, draft recovery and failed-commit UX. Define remote revocation versus residual JWT lifetime and in-flight server commits. Never erase an outbox as error recovery. |
| Account/public-cache composition | Define approved catalogue + account/private + pending-local view composition, environment scoping, deduplication, source attribution, stale/deleted visibility and ranking inputs. Cache records remain separate protocol snapshots, not UI domain rows. |
| Consent and association | Approve separate private-history/favourites consent and explicit previewed guest-data association with eligible provenance, duplicate protection and atomic retry. Neither authentication nor `user_created` provenance grants these capabilities. |
| Recoverable errors | Provide validation/conflict UX retaining the original local content and rejected/conflicted command; expose remote revision/content, explicit correction/retry/resolution and blocked dependencies. Do not silently discard, truncate, normalize away content or automatically overwrite conflicts. |
| Unicode compatibility | Resolve the server codepoint/emoji-subset versus Flutter extended-grapheme mismatch with equivalent segmentation, or explicitly approve an explained remote bound and recoverable validation UX. Preserve current local input semantics. |
| Portability | Rehearse export/restore or define a safe new epoch for the new synchronization metadata: outboxes/receipts/dependencies, revisions, conflicts, retries, tombstones, log and cursors. Earlier managed-exit evidence predates this metadata. |
| Public identity/publication | Approve public profile creation, attribution, review publication, moderation, retention and erasure. Account authentication and private backup must not create public identity/content. |

## Verification scope

`test/account_state_test.dart` covers local guest/account initialization, A/B/environment isolation, session states/renewal/expiry/logout/switching, delayed renewal/store/submit/pull responses, explicit fixture queueing versus identity, pending restart, transaction failure, draft barriers and safe disposal. `test/storage_ui_test.dart` exercises actual review/bathroom draft controllers across session loss and verifies Provider route replacement/listener removal. All prior ordinary regressions remain included.

Run formatting, the unchanged exact analyzer baseline, all ordinary Flutter tests, all offline backend tests and Linux/Android debug builds. Final executed counts are recorded in [ROADMAP](../../ROADMAP.md). Real backend integration is not rerun: no server protocol, SQL migration, HTTP transport or remote method contract changed. The seven real integration tests passed at baseline `321d1ea`; that historical result is not claimed as a new run. No managed project or preserved backend installation is accessed.
