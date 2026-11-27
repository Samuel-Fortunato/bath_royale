# A6.1 performance and stability investigation

Status: targeted fixes verified on 2026-11-27; owner acceptance and historical ANR attribution remain open. This work takes priority over new features. The owner's reproduction guidance is **online, especially following refresh and opening menus/pages**. No new GitHub release is authorized; `ALPHA_RELEASE_APPROVED` was read back as `false`.

## Physical baseline and method

The connected Samsung SM-A166B had **0.1.0-alpha.1038 / code 1038**, not published code 1039. The actual APK was pulled and verified as a universal, non-debuggable AOT release with the original certificate `4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`; SHA-256 `909a0d48cf241ad20c37d8468891ac90ae6f1779d3bfffa0e023313027569c54`. First installation: **2026-11-26 22:40:55**, app UID 10419. No uninstall, data clear, schema reset, account substitution or guest import was performed.

The baseline cold Android activity launch reported 332 ms. App-scoped logcat subsequently recorded **167 skipped frames**. Android's retained exit information and last-ANR summary identify an earlier **10,002 ms focus-event input timeout at 08:42:46**. The summary contains no Dart/SQLite stack establishing its cause; do not declare that ANR fixed from the calculation measurements alone. Driver buffer-format probe errors and an ashmem deprecation also occurred at startup; there is no evidence that they caused the recurring stalls.

Read-only device workloads exercised Explore pull-to-refresh, Collection, Rankings, Profile, bathroom details/back and scrolling. CPU was sampled with `top` at one-second intervals; memory with `dumpsys meminfo`. `gfxinfo` reported only the Android host view, not the Flutter frame workload. SurfaceFlinger reported 76 app buffers, but no per-layer frame-timeline classifications; idle presentation gaps are not evidence of jank. Neither is used as a Flutter jank percentage.

For attributable measurements, `tool/performance_probe.dart` runs the real state/storage/ranking code and existing application widgets in **release AOT** on the same phone. Its separate package is `com.example.bath_royale.performance`, labelled **Bath Royale — Medição**. It uses memory-only SQLite, a fake remote and explicitly fictional identities/content. It cannot read the ordinary app's files, credentials or managed data. Gradle requires both that target and `BATH_PERFORMANCE_PROBE=true` together, preventing accidental package replacement. No debug-mode timing or DevTools debug result is used.

Each size has N bathrooms, 10N private visits, 5N private reviews and 10N public reviews. The probe records three entry and ranking calculations and then renders the 34-bathroom application, selects all four destinations three times and refreshes between rounds. Flutter's timing callback records build/raster durations. The baseline used application source `aa25849`; the ordinary app code matches the initial alpha source. Instrumentation/fixtures are identical for the comparison. These are controlled local calculations and a scripted UI workload, not a production-network load test.

## Confirmed causes and changes

1. `allBathrooms` decoded the entire SQLite catalogue separately for each retained bathroom. Visibility checks, each entry's activity/chronology and per-review link resolution repeated that work and further SQL queries. With 100 bathrooms, three entry/ranking computations invoked the bathroom getter **61,806 times**. These synchronous main-isolate reads can stall interaction even when the network has already responded.
2. Rankings scanned every review for every bathroom and repeatedly queried the identity-link table through its callback. Grouping scores in one review pass and capturing links once in the page preserves all means, counts, scopes and deterministic ties.
3. A second `CommunityCatalogue.refresh()` returned a completed future while the first pull was still pending. A delayed-transport regression reproduced the premature completion before the fix. The shared future is published before synchronous listener notification, preventing reentrant duplicate pulls. Concurrent callers now join the same future, so refresh indicators and post-sync projection wait for the actual result.

The state changes build short-lived snapshots and group reviews/visits/favourites once per computation. They preserve historical links, latest-review visit chronology, other-author isolation, zero ratings, published-only community scores and immediate visibility of cache changes/withdrawals. No persistent derived cache, new dependency, schema/index migration, disabled validation, weaker authentication or altered server protocol is introduced.

## Before/after results

Medians of three release-mode calculations; milliseconds:

| Same phone/workload | Before | After |
| --- | ---: | ---: |
| 34 bathrooms: entries | 574.787 | 3.260 |
| 34 bathrooms: rankings | 80.207 | 5.039 |
| 100 bathrooms: entries | 9,968.136 | 14.262 |
| 100 bathrooms: rankings | 690.185 | 16.589 |
| Bathroom getter calls, three 34-entry/ranking runs | 7,554 | 12 |
| Bathroom getter calls, three 100-entry/ranking runs | 61,806 | 12 |

A second candidate measurement reproduced 2.985/6.395 ms median entries at 34/100 bathrooms and a 71.620 ms maximum build frame.

The scripted rendered workload's maximum Flutter build duration fell from **3,610,460 µs to 78,120 µs**. Baseline: 282 frames, two builds and two raster frames above 16.667 ms; after: 457 frames, three builds and three raster frames above that threshold. Maximum raster duration: 52,709 → 29,378 µs. This removes the measured multi-second stall; it does **not** establish completely jank-free rendering. The baseline's blocked UI generated fewer frames; compare maximum stall and calculation cost, not raw slow-frame counts as an improvement percentage.

The ordinary installed release and in-place RC ran the same read-only refresh/navigation command sequence. Twelve CPU samples averaged **70.8% → 24.2% of one core**, peaks **101% → 48%**. These short samples are indicative: ADB start alignment, network timing, background load and thermal state were not pinned. The AOT calculation comparison is the stronger attributable evidence.

Post-workload installed-app PSS was **136,104 → 140,168 KiB**, RSS **210,971 → 218,179 KiB**. No memory improvement or leak resolution is claimed. Isolated-probe idle CPU was 0%; a longer retention/allocation trace is still needed to establish leak behavior.

RC cold activity launch was 484 ms (415 ms after the final rebuild); a foreground return took 56 ms without starting another activity. Cold-launch samples do not establish a startup improvement, and activity timing excludes asynchronous application readiness/authentication. Inspection confirms restoration uses the secure local session without a network request; existing restoration/expiry/isolation tests pass.

Four ordinary anonymous HTTPS catalogue pulls measured **531/244/188/205 ms**, **4,626/5,635/939/102 bytes**, and **20/20/4/0 changes**. Payloads/checkpoints were not logged. This small public sample does not implicate payload size and does not characterize private-account latency, every retry or slow mobile networks. No privileged query or managed catalogue mutation/fixture/reset was used.

## Verification and artifacts

- **248 Flutter tests pass**, five opt-in placeholders skipped; formatting and the existing strict analysis policy pass. New regressions bound catalogue reads as the catalogue grows, preserve linked history/favourites/foreign-author separation, count one ranking identity resolution per eligible review, join delayed refreshes, prevent synchronous refresh reentry, and navigate/commit a durable favourite during a stalled/failed pull followed by reconnection.
- Disposable community runner: actual two-account Flutter contribution/review/edit/withdrawal/offline-cache test, **64 API/privacy/entitlement assertions**, complete export/restoration. Disposable protocol runner: **1,093 Unicode cases, 601 real server protocol assertions, eight real Flutter sync tests**, profile-free privacy checks and complete metadata/receipt/cursor/sequence/clock restoration. Both dedicated stacks stopped afterward; preserved phone/managed infrastructure was not reset.
- **38 offline backend tests**, **16 tooling tests**, actionlint, Android universal signed release and Linux release builds pass. The normal analysis gate retains only its exact reviewed Material-import baseline.
- Original and RC certificates, package, version, universal AOT/non-debuggable payload and absence of fixture/probe/local-TLS material were verified. Public HTTPS configuration is present in each RC architecture; no privileged credential is compiled into it.

The signed owner-test RC is `/tmp/bath-royale-a61-rc1040.apk`, **0.1.0-alpha.1040 / code 1040**, **61,991,038 bytes**, SHA-256 **`b7130db106ef66b699ce38417d26e727f58e25feb003158455c4a4f63811c0b9`**. It was installed using only `adb install -r`; the original certificate/UID and first-install timestamp remain. The existing account and catalogue opened without another login. Device-side database contents are not exported or exposed as diagnostics. Normal sync may advance its metadata; no byte-for-byte database comparison is claimed.

Local diagnostic evidence (outside Git): `/tmp/a61-before.jsonl`, `/tmp/a61-after.jsonl`, `/tmp/a61-installed-before-cpu.txt`, `/tmp/a61-installed-after-cpu.txt`, `/tmp/a61-public-network.json` and `/tmp/a61-*.log`. The JSONL files contain aggregate fictional-probe measurements only. Private screenshots and installed APKs are not committed or published. A physical review-wizard check in the isolated fictional app selected a rating/categories/tag and saved successfully back to details; it did not publish managed content or test real-account submission.

Initial probe compilation failures (missing timing import/type inference), test setup/assertion mistakes and a fresh-state backend attempt were corrected before the final passing checks. The backend correctly refused an existing volume without matching credentials; verification then used that disposable instance's existing credential directory. No volume was cleaned to bypass the guard.

## Reproduce the isolated measurement

Use the existing Nix/direnv environment. Build and inspect the package before installation:

```sh
BATH_PERFORMANCE_PROBE=true flutter build apk --release --no-pub \
  --target tool/performance_probe.dart --target-platform android-arm64 --build-number 1
"$ANDROID_HOME/build-tools/36.0.0/aapt" dump badging build/app/outputs/flutter-apk/app-release.apk
# Require com.example.bath_royale.performance, never the ordinary package.
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -W -n com.example.bath_royale.performance/com.example.bath_royale.MainActivity
# Read only A61 lines for this process; the final record is named "done".
adb shell pidof com.example.bath_royale.performance
```

To rerun the old algorithm, use a separate checkout at `aa25849` and copy only the measurement target plus its Android identity/label guard into that checkout. Do not revert the owner's working tree or install an old ordinary app. Keep the same fixture sizes, phone and workload; retain both APKs and aggregate output. Normal builds use `lib/main.dart` and the original application identity. Do not invoke the publication helper or change the approval gate to build a local RC.

## Remaining limitations and owner physical acceptance

SQLite loading/projection still runs synchronously. Repeated materialization, full projection, residual first-frame work, many more than 100 bathrooms/1,000 activities, prolonged navigation, subscriptions and allocations need additional traces if the problem persists. No main-isolate migration or incremental projection is justified solely by the currently measured network timings. No complete private HTTP request-frequency trace, cellular throttling test or second physical device comparison was performed. Existing bounded foreground scheduling, retry/backoff, disposal and account-generation guards remain covered by tests. No claim that the historical ANR has a proven stack-level root cause is made.

On the installed **code 1040** candidate:

1. Open after a cold process start and after Home/resume. Confirm the expected account, retained history, favourites and appearance. Pull Explore to refresh three times; while a refresh is pending, immediately change to Collection, Rankings and Profile, open a bathroom and return. Record the exact screen/time if it stops responding.
2. Scroll Explore, Collection and diary histories; change ranking scope/category/order, open ranked details and use system Back. Check personal/community scores, zero ratings and visit chronology.
3. In your own account, deliberately submit one review using the existing wizard; verify immediate local history/collection/ranking behavior, then verify synchronization. Exercise creation/feedback/administrator controls only with intentional valid actions; automation did not submit owner content or feedback.
4. Disable networking manually, reopen the app, create an intentional visit/review and toggle a favourite. Confirm navigation stays responsive and committed work survives a process restart. Restore networking, foreground the app and verify eventual synchronization without duplicate reviews or lost edits. Do not clear storage or uninstall.
5. On a slow connection, repeat refresh/navigation and local submission. If available, use a second signed-in device to check account convergence, then test logout/relogin and A/B isolation after finishing all editors. Preserve unsent drafts in their original account.
6. Report any remaining freeze with timestamp, action, connection state and whether it followed opening/resuming or refresh. Collect only app-scoped sanitized diagnostics around that timestamp; investigate a new ANR with its actual stack before declaring A6.1 complete.

Passing these steps is owner acceptance of this candidate, not permission to publish it. A new GitHub release and enabling `ALPHA_RELEASE_APPROVED` require separate owner approval.
