# Catalogue reconciliation and v0.1.1 candidate

Status on 2026-11-27: implementation, automated checks and operator-observed in-place verification complete. **The owner physically tested and approved all v0.1.1 performance and catalogue fixes and explicitly authorized publication. A6 is closed; see [release evidence](releases/v0.1.1.md).** The owner physically tested and accepted the performance improvements in `97e14ae`; those improvements are included unchanged.

## Cause and reconciliation rules

`AppState._sharedIds` combined the public cache with every ID in account `catalogue_bathrooms`. That table retains shared parents for personal references and never removes them on public deletion. `visibleBathrooms` mistakenly used that identity membership as public availability. After the public cache received a removal, its materialized account parent remained visible. Materialization and `AccountProjection.sharedBathroom` also inserted only missing parents, so updated public metadata could disappear after restart or withdrawal.

The durable environment-scoped public `remote_records` cache now determines catalogue visibility. Account `catalogue_bathrooms` remains an identity/provenance registry for personal history, not a second public catalogue. Local contributions can remain visible while awaiting public delivery; an explicit public withdrawal suppresses even an unresolved contribution without removing its operation. Account projections cannot make an unavailable public identity visible.

`materializeCatalogue()` runs on attachment and completed refresh notifications as well as before personal operations. It updates existing shared names, normalized names, emoji, palette/RGB and classification in one account transaction, then refreshes in-memory parent metadata. Account shared projections use the same parent upsert; current public metadata takes precedence when account data reloads. Existing locally owned/demo/legacy parents are not taken over. No projection queues a new operation.

A removal changes availability, not personal identity. Bathroom parents, `catalogue_bathrooms`, links, visits, reviews, favourites, outbox payloads/dependencies and other sync metadata are retained. Personal history continues to use known shared identities. The diary looks up retained parents rather than visible catalogue rows; details already open during withdrawal render an unavailable page safely. Restoring the same identity restores catalogue membership with its current metadata and existing personal records.

No count-based pruning, cache clearing, schema reset or inferred deletion from an absent refresh page is used. `SyncStore.applyPull` continues atomically committing each page, revisions, tombstones and checkpoint. Unseen cached records survive partial/failed refreshes and offline restart. An explicit `deleted:true` record removes availability immediately. `_visibility:false` is reversible; a later accepted public projection restores it. An empty terminal tombstone rejects later upserts. The existing server's historical public feed resolves current visibility and can represent a physically missing row with the visibility marker; both forms suppress the entry. No backend migration or managed mutation is needed for this fix. Already downloaded stale public rows remain available offline until their removal arrives; this is intentional offline behavior, not evidence of live availability.

Existing installations repair themselves from their retained public cache on attachment; any not-yet-received removal arrives through ordinary incremental refresh. Private replay can retain a parent but never overrides public availability. No reinstall, local-file deletion, checkpoint reset or account switch is required.

## Verification

- **258 Flutter tests passed**, five opt-in integration placeholders skipped. Ten new regressions exercise reopening the same SQLite files with 36 retained parents and reconciling visibility to 30 while comparing complete personal/outbox rows; hide/restore and visual metadata durability; terminal resurrection rejection; bounded/failed refresh and checkpoint retention; private shared projections and bathroom tombstones; pending contributions; atomic failed-page rollback; historical diary navigation and an open detail page during withdrawal. Existing bounded-read/performance regressions still pass.
- Strict analysis passed with only its existing exact Material-import baseline; Dart formatting passed for 88 files. **16 tooling tests**, actionlint and Git whitespace checks passed. Backend suite: **38 tests run, two opt-in tests skipped, all remaining tests passed**; the old CSV test expected 34 rows and Antiga Reitoria last, and was corrected to the owner's current 30-row CSV, one general DETI and Cantina last. No CSV or managed data was modified.
- Android universal signed release and Linux release builds passed. APK verifier confirmed the original certificate, package, exact version, non-debuggable three-ABI AOT and no debug kernel. Each AOT payload contains the managed public HTTPS configuration; known fixture identities, fixture selectors, probe marker and local TLS material are absent. No privileged credential is supplied to this build.
- A read-only anonymous `public_catalogue` request returned **30 bathrooms and exactly one DETI entry**. No operator SQL, import, seed, moderation or managed data/schema change was executed. The phone continues its ordinary app synchronization.

Initial verification failures were corrected: the existing backend test had stale CSV expectations; fault injection and widget-shell setup needed adjustment; a missing SDK Material replacement import was removed in favour of the existing test harness; one new lint was fixed. The final checks above were rerun successfully. No failed check is counted as passing.

## Existing installation and private artifact

The existing SM-A166B ran approved `0.1.0-alpha.1040`, code **1040**. Before updating, read-only UI inspection reproduced **7 DETI search results** (general DETI plus deleted floors) and Collection **0 / 36**. Personal aggregates were **0 visits / 0 reviews / 0 favourites**.

The signed candidate is `/tmp/bath-royale-v0.1.1-rc1045.apk`:

- Version **0.1.1-alpha.1045**, Android code **1045**, package `com.example.bath_royale`.
- **61,991,038 bytes**, SHA-256 **`91b9bfcfe642d7441ea29488034adc76b395a7748a6f4cc847d961458baac9aa`**.
- Original certificate SHA-256 **`4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`**.

Only `adb install -r` was used. The account opened without signing in again. App UID **10419** and first-install timestamp **2026-11-26 22:40:55** remained unchanged. Post-update search showed **1 DETI result**, Collection showed **0 / 30**, and the original zero personal counts remained. A cold process restart with airplane mode enabled retained the signed-in navigation, **30** catalogue entries and the original personal counts. Airplane mode was restored to its original disabled state, then the app was foregrounded online again. No uninstall, storage clear, account substitution or synthetic owner activity was performed. Non-empty history/outbox preservation is established by persisted-database regressions, not falsely inferred from this phone's empty personal aggregates. Device databases and secure sessions were not exported or byte-compared.

Private XML/verification receipts are under `/tmp/catalogue-*`; no private device captures or APKs enter Git. Version 1045 exceeds the installed code and aligns with the next workflow sequence after run 44. A future authorized published build must use a fresh workflow number and a code greater than the candidate installed then; do not reset the workflow counter.

## Owner acceptance and publication

The owner confirmed physical acceptance of all v0.1.1 performance and catalogue reconciliation fixes in the A6 closure/A7.1 instruction. The approved release is [Bath Royale v0.1.1 — Alfa](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1046), code **1046**, greater than installed candidate 1045. The existing controlled workflow passed; actual APK, original certificate/package/version/checksum and anonymous downloads were independently verified. It is Latest; the previous alpha and Git history remain preserved.

`ALPHA_RELEASE_APPROVED` was restored to **false** once the approved build captured its gate. README links now point to the verified release. See [complete publication evidence](releases/v0.1.1.md). No managed data/schema change, device uninstall or reset was performed during publication.
