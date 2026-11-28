# Release presentation and versioning

The current user-facing version is **v0.1.1**, titled **Bath Royale v0.1.1 — Alfa**, published as **Latest**. Its immutable identity is `alpha-1046`, APK versionName `0.1.1-alpha.1046`, Android versionCode `1046`. See [publication evidence](v0.1.1.md). Previous `alpha-1039` remains preserved. Presentation edits do not alter identities, signing, assets or download URLs.

Future titles use `Bath Royale v<major.minor.patch> — Alfa`; development builds are never published. The semantic version comes from `pubspec.yaml`, excluding build metadata; change it only as an explicitly scoped application release decision. Android build codes are monotonically increasing internal update identifiers, shown separately in the technical details, never as public version numbers. The `alpha-<code>` tag shape remains unchanged; A7.4 allocation below supersedes the old workflow-counter formula. “Primeira Alfa” applies only to this inaugural publication; subsequent publications use the generic Alfa label.

`tool/publish_preview.py` generates future titles and Portuguese bodies from that source version and `alpha-notes.md`, appending the internal build and source commit. Keep that template current before an authorized publication. It preserves draft-first checks, byte comparisons and refusal to modify published assets. Existing releases require deliberate metadata-only edits; normal retries never rewrite published releases. The publication gate remains disabled and must not be enabled for presentation maintenance. README download links deliberately pin the approved alpha: update them after verifying a future authorized release, rather than linking to `/releases/latest` (which excludes pre-releases).

## Historical release cleanup — 2026-11-27

The owner explicitly approved removal of every historical `preview-*` GitHub release and its assets, superseding the earlier recommendation to retain selected evidence releases. Removed **24 releases**: the empty `preview-1014` draft and published `preview-1015` through `preview-1037`, including **46 assets**. No `preview-1038` release existed. All 46 removed asset API endpoints returned HTTP 404 after cleanup. Git tags, their target objects, commits and source history were preserved; deletion used only the GitHub release API, never tag deletion.

At that historical cleanup, `alpha-1039` was the only remaining GitHub release. Its title, body, pre-release flag, identity, APK/checksum asset IDs, digests and download URLs were compared before/after and preserved. Anonymous download still matches the original size and checksum below. The publication gate remains `false`.

Historical verification remains in [Android preview operations](../android-previews.md): source SHAs, hosted-run links, APK sizes, checksums and signing/version observations describe the tests performed at that time. Removed preview releases have no live download links in this documentation; preserved source tags remain available in Git. This cleanup does not retract historical verification or claim new compilation.

Future development builds are validation-only: workflow upload/publication conditions require a configured alpha, and the publisher independently rejects unconfigured development invocations before any file or network access. Only separately approved configured alphas can publish. Tests cover both workflow conditions, publisher rejection and alpha draft/retry integrity. No application rebuild, version change, backend operation or gate activation was performed for cleanup.

## Presentation verification

On 2026-11-27 the existing alpha APK and checksum were downloaded anonymously from their original URLs. The APK remained 61,974,654 bytes and matched SHA-256 `8f08897043cbb03849165f0899e2e14fe18750793ec32502b70f7272c9a09a5f`. No APK was rebuilt or republished. The gate read back as `false`.

Cleanup checks passed: 16 tooling tests, actionlint, Dart formatting, the existing strict analysis gate, changed-document local links and Git whitespace checks. No application build was run for this task.


## A7.4 version and build protocol

`tool/app_version.py` protocol 1 reads the single canonical `version:` in
`pubspec.yaml`. It exposes semantic version, explicit channel, versionName,
versionCode, package and runtime version. `bump()` previews major/minor/patch and
writes only with explicit application. Build scripts, installer and publisher
reuse it. Android runtime feedback reads actual PackageInfo; unsupported runtimes
report `desconhecida` when no build define exists, never an invented old version.
The manager version remains independent. A7.4 does not bump or publish v0.1.1.

Development uses code **1**, `<semantic>-dev.1`, and the separate
`com.example.bath_royale.development` package. It is validation-only and never a
managed candidate/public release. Both retained isolated installer targets require
that package; the old path that could replace the managed package is refused.
The performance probe retains its separate `.performance` identity. Managed
candidates use the original `com.example.bath_royale`, certificate SHA-256
`4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`, and
`<semantic>-alpha.<code>`. Original installed releases remain update-compatible.

### Shared monotonic allocator

`tool/release_ledger.py` uses the dedicated append-only Git branch
`managed-build-ledger` in this application repository. No ledger mutation occurs
until an explicit candidate build. Its JSON contains only public source/version/
allocation and approval hashes, never credentials. Each update creates a child of
the observed head and updates the ref with `force=false`. Concurrent sibling
commits cannot both win. Retry contention up to eight times; then stop. Requests
use a caller-retained 32-hex UUID, bound to one exact source SHA and semantic
version. A retry returns the same allocation; a different request consumes a new
code even if the build failed. An unknown network outcome requires retrying the
**same** request. Never reset, force-update, delete or recreate this branch. An initial `managed-build-ledger-origin` tag anchors bootstrap before branch creation. If the branch is absent but that anchor exists, allocation fails closed; an owner must reconcile the exact anchored object and interrupted request rather than initialize a new counter. Neither marker nor branch is created by A7.4 acceptance.

On 2026-11-28 actual preserved tags ranged from preview-1014 through alpha-1046;
latest published/retained managed APK was code 1046. The old Android workflow's
last validation was run 58 (`1000+58=1058`), without a distributable artifact. The
old private installer reused the installed code; it did not allocate new codes.
The migration fence reserves **all codes through 1,000,000**, including those
legacy values. New allocations are `max(fence, all remote release-tag codes,
all committed allocations, explicitly observed installed minimum)+1`, at most
2,100,000,000. The first normal candidate is therefore **1,000,001**. No unrelated
workflow counter, wall clock, machine counter or local file allocates managed
codes. Local and future GitHub managed builds must use this same interface.
Ordinary hosted validation consumes no managed code. An existing unsupported APK
with a higher code blocks installation: inspect it and pass the actual observed
code as `--minimum` on a **new** allocation. Do not guess, downgrade or reset it.

All supported managed candidates have a ledger allocation. Publication accepts
only the newest allocation and requires both a higher semantic version and code
than the actual latest public release. This prevents a public update from falling
behind a supported installed candidate. No allocation occurs while publication is
pending. A filesystem lock also prevents overlapping local Flutter builds sharing
canonical artifact storage; every resulting APK is independently verified.

### Controlled publication and recovery

`tool/managed_release.py` protocol 1 receives JSON on stdin. The private manager
is its presentation/custody adapter; Flutter, Gradle, `build_alpha.py`,
`verify_preview.py`, payload scanning and `publish_preview.py` remain app-owned.
Ordinary Android CI is validation-only, with no write permission, upload or
publication job, even if a repository variable was accidentally left enabled.
Publication moved from an ambient variable-triggered CI job to an exact reviewed
manager operation using the existing draft-first publisher. This is intentional:
a boolean alone must never approve a different push or a workflow rerun.

Publication previews a digest binding the exact current official main commit,
clean/equal-upstream source after fetch, current semantic version, newest global
allocation, verified APK checksum/original certificate, reviewed notes, validated
public configuration and successful latest attempts of both Android and backend
CI for that exact SHA. `--confirm <digest>` is explicit owner approval of that
operation. Approval is checked again before public exposure. CI credentials stay
in independently authenticated gh; existing Actions signing secret is not read or
updated. Local signing uses protected SOPS-derived paths and password files.

The shared ledger grants one 90-minute publication lease. Concurrent publication,
new candidates, expired/stale bindings and changed CI attempts are rejected. Only
that operation enables ALPHA_RELEASE_APPROVED, reads it back, publishes a draft
with exact tag/source and immutable byte comparisons, then exposes the verified
assets as `Bath Royale v<semantic> — Alfa`, a stable GitHub release marked Latest.
The body still explicitly describes alpha limitations. Previous releases/tags stay.
After exposure, anonymous HTTPS download verifies the actual APK, checksum, asset
digests/size, public metadata, tag SHA and original signing identity. README links
must only change after this succeeds; they remain pinned during A7.4.

Normal completion, exceptions and handled termination disable and read back the
gate in finally. Only complete verified publication frees the lease. Failures
retain exclusion for reconciliation. Hard kill, power loss or interrupted network
cannot guarantee remote cleanup: inspect the exact pending state with manager
`release reconcile`, then confirm its digest to disable/read back the gate. An
expired lease plus explicit `--publisher-stopped` owner confirmation is required
to free exclusion. A live lease remains blocking. This never resumes publication,
removes a tag/release, changes secrets or claims an incomplete release succeeded.
If an unrecorded gate is true with no lease, reconciliation still disables it.

An incomplete artifact directory is never overwritten, including symlink destinations. Preserve/review its exact files before explicitly moving that failed attempt aside and retrying the same request into its empty canonical directory. Exclusive 0600 file creation also refuses a destination appearing during the operation. A failed build consumes its allocation: fix source/configuration and allocate a
new candidate, or retry the same request only for an identical source/version.
Failed CI is inspected via selected run/job; only safe validation workflows can be
rerun. Conflicting tags or incomplete published assets require individual review;
never replace/delete public assets automatically. Draft retries compare every
existing byte before uploading missing assets. Invalid signatures stop before
installation/publication. A faulty public release needs a corrective **newer
semantic version and Android code**, retaining the original signing identity.
Both ledger-backed candidates and verified public downloads can be installed as guarded forward updates. Archived candidates derive their version from pubspec at their recorded source commit, so a later source bump does not invalidate artifact inspection. Source rollback means reverting source in Git and creating that new release. It
never authorizes Android downgrade, uninstall, data clearing or promises of old
APK/database compatibility. Preserve historical releases and failed evidence.
