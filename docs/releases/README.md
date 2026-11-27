# Release presentation and versioning

The current user-facing version is **v0.1.0**, titled **Bath Royale v0.1.0 — Primeira Alfa**. Its immutable distribution identity is `alpha-1039`, APK versionName `0.1.0-alpha.1039`, Android versionCode `1039`. Presentation edits do not alter these identities, signing, assets or download URLs.

Future titles use `Bath Royale v<major.minor.patch> — Alfa` (or `Desenvolvimento` for internal previews). The semantic version comes from `pubspec.yaml`, excluding build metadata; change it only as an explicitly scoped application release decision. Android build codes are monotonically increasing internal update identifiers, shown separately in the technical details, never as public version numbers. Existing build-name/code generation and `alpha-<code>` tags remain unchanged. “Primeira Alfa” applies only to this inaugural publication; subsequent publications use the generic Alfa label.

`tool/publish_preview.py` generates future titles and Portuguese bodies from that source version and `alpha-notes.md`, appending the internal build and source commit. Keep that template current before an authorized publication. It preserves draft-first checks, byte comparisons and refusal to modify published assets. Existing releases require deliberate metadata-only edits; normal retries never rewrite published releases. The publication gate remains disabled and must not be enabled for presentation maintenance. README download links deliberately pin the approved alpha: update them after verifying a future authorized release, rather than linking to `/releases/latest` (which excludes pre-releases).

## Historical release review — 2026-11-27

Read-only GitHub inventory found 25 releases, including one empty draft. No release, asset or tag was deleted.

| Recommendation | Releases | Reason |
| --- | --- | --- |
| Keep | `alpha-1039` | Current configured managed alpha and README download target. |
| Keep as historical evidence | `preview-1015`, `preview-1023`, `preview-1024`, `preview-1025` | Referenced publication/retry and debug-to-AOT comparison evidence in Android preview documentation. |
| Candidate for removal with owner approval | `preview-1014` | Empty unpublished draft; no assets. Check associated tag before a separately approved cleanup. |
| Candidates for removal with owner approval | `preview-1016`–`preview-1022`, `preview-1026`–`preview-1037` | Superseded development APKs, unsuitable as the current managed alpha download. Removing them would break their historical asset URLs. |

Low download counts (2–4 per asset at review, including verification traffic) do not prove there are no external users or links. Preserve tags by default even if release removal is later approved; review documentation references again before deleting anything. No `preview-1038` release appeared in the inventory. This is a recommendation, not cleanup authorization.

## Presentation verification

On 2026-11-27 the existing alpha APK and checksum were downloaded anonymously from their original URLs. The APK remained 61,974,654 bytes and matched SHA-256 `8f08897043cbb03849165f0899e2e14fe18750793ec32502b70f7272c9a09a5f`. No APK was rebuilt or republished. The gate read back as `false`.
