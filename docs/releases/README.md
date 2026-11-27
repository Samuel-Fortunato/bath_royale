# Release presentation and versioning

The current user-facing version is **v0.1.1**, titled **Bath Royale v0.1.1 — Alfa**, published as **Latest**. Its immutable identity is `alpha-1046`, APK versionName `0.1.1-alpha.1046`, Android versionCode `1046`. See [publication evidence](v0.1.1.md). Previous `alpha-1039` remains preserved. Presentation edits do not alter identities, signing, assets or download URLs.

Future titles use `Bath Royale v<major.minor.patch> — Alfa`; development builds are never published. The semantic version comes from `pubspec.yaml`, excluding build metadata; change it only as an explicitly scoped application release decision. Android build codes are monotonically increasing internal update identifiers, shown separately in the technical details, never as public version numbers. Existing build-name/code generation and `alpha-<code>` tags remain unchanged. “Primeira Alfa” applies only to this inaugural publication; subsequent publications use the generic Alfa label.

`tool/publish_preview.py` generates future titles and Portuguese bodies from that source version and `alpha-notes.md`, appending the internal build and source commit. Keep that template current before an authorized publication. It preserves draft-first checks, byte comparisons and refusal to modify published assets. Existing releases require deliberate metadata-only edits; normal retries never rewrite published releases. The publication gate remains disabled and must not be enabled for presentation maintenance. README download links deliberately pin the approved alpha: update them after verifying a future authorized release, rather than linking to `/releases/latest` (which excludes pre-releases).

## Historical release cleanup — 2026-11-27

The owner explicitly approved removal of every historical `preview-*` GitHub release and its assets, superseding the earlier recommendation to retain selected evidence releases. Removed **24 releases**: the empty `preview-1014` draft and published `preview-1015` through `preview-1037`, including **46 assets**. No `preview-1038` release existed. All 46 removed asset API endpoints returned HTTP 404 after cleanup. Git tags, their target objects, commits and source history were preserved; deletion used only the GitHub release API, never tag deletion.

At that historical cleanup, `alpha-1039` was the only remaining GitHub release. Its title, body, pre-release flag, identity, APK/checksum asset IDs, digests and download URLs were compared before/after and preserved. Anonymous download still matches the original size and checksum below. The publication gate remains `false`.

Historical verification remains in [Android preview operations](../android-previews.md): source SHAs, hosted-run links, APK sizes, checksums and signing/version observations describe the tests performed at that time. Removed preview releases have no live download links in this documentation; preserved source tags remain available in Git. This cleanup does not retract historical verification or claim new compilation.

Future development builds are validation-only: workflow upload/publication conditions require a configured alpha, and the publisher independently rejects unconfigured development invocations before any file or network access. Only separately approved configured alphas can publish. Tests cover both workflow conditions, publisher rejection and alpha draft/retry integrity. No application rebuild, version change, backend operation or gate activation was performed for cleanup.

## Presentation verification

On 2026-11-27 the existing alpha APK and checksum were downloaded anonymously from their original URLs. The APK remained 61,974,654 bytes and matched SHA-256 `8f08897043cbb03849165f0899e2e14fe18750793ec32502b70f7272c9a09a5f`. No APK was rebuilt or republished. The gate read back as `false`.

Cleanup checks passed: 16 tooling tests, actionlint, Dart formatting, the existing strict analysis gate, changed-document local links and Git whitespace checks. No application build was run for this task.
