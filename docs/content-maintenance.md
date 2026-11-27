# Owner-maintained alpha content

A5.2 integrates the owner's approved content. A5.3 deployment status is recorded in [managed acceptance](backend/managed-alpha-acceptance.md); [manual alpha operations](backend/alpha-operations.md) define backup and retention responsibilities. Maintain only these sources:

| Source | Purpose |
| --- | --- |
| `content/official_bathrooms.csv` | Genuine official catalogue, separate from development fixtures |
| `lib/models/content_suggestions.dart` | Review tags, emoji suggestions, RGB swatches and decorative progression |
| `assets/branding/app-icon.png` | Original approved launcher artwork |

## Official bathrooms

The original import contained 34 entries. The owner-maintained CSV now contains 30 entries, including general DETI and Cantina, following the separately performed catalogue maintenance. The [v0.1.1 reconciliation fix](catalogue-reconciliation.md) makes existing app caches follow that managed catalogue without reimporting or changing managed data. Entries preserve the exact approved abbreviated names, emoji and RGB values. A general department entry deliberately covers that department until specific bathroom locations are known. Do not expand abbreviations or invent ratings/location detail. Importing creates only bathroom records: no accounts, reviews, tags, visits or favourites.

Add a CSV row with a new permanent lowercase hyphenated `key`, exact name, one emoji grapheme and `#RRGGBB`. Never rename, reuse or delete an established key to correct appearance. UUIDs are UUIDv5 with `uuid.NAMESPACE_URL` and `bath-royale:official-catalogue:v1:<key>`; this derivation is permanent. Correct name, emoji or color in the existing row. Review the CSV diff with the owner before applying significant catalogue changes. The initial official CSV is not bundled into the app and never runs at startup.

`backend/import_catalogue.py` emits SQL only; it never connects to a database or calls a privileged client API. Apply migrations through `017` first. Use the existing verified-TLS, private operator connection environment described in [release preparation](backend/alpha-release-preparation.md). Never put credentials in command arguments, source or CI logs.

```sh
python3 backend/import_catalogue.py --output /tmp/catalogue-dry-run.sql
# Review SQL, then execute against the approved target:
psql -X -f /tmp/catalogue-dry-run.sql
# Only after dry-run review and target/backup checks:
python3 backend/import_catalogue.py --apply --output /tmp/catalogue-apply.sql
psql -X -f /tmp/catalogue-apply.sql
```

Outputs are created exclusively; choose a fresh path for another plan. Local CSV validation catches malformed rows/keys/RGB and duplicate keys/names/UUIDs; database dry-run additionally checks the current emoji/name constraints, identity registry, domain baseline and normalized shared-name collisions. Dry-run writes no permanent rows, feed entries or sequences. It takes short-lived locks and rolls back. Apply revalidates under the normal sync-writer lock and table locks, atomically commits the whole batch and preserves publication/change triggers. Run during the quiescent deployment window.

`app_private.official_catalogue` stores each key, UUID and last-applied content. It is RLS-protected, inaccessible to anon/authenticated/service-role clients, and included in logical backups. New rows use `origin=curated`, `community=true` (shared domain flag), `account_private=false`, approved publication and verified classification. Public RPCs/feeds display **official**. There is no contributor account or synthetic review. Existing matching imports perform no updates, preserving timestamps and feeds. Corrections preserve UUIDs, associations and activity.

The importer refuses an occupied UUID without its matching registry entry, registry mismatch, external change to any managed domain field, or normalized-name collision (including hidden shared rows). It does not silently adopt, merge, unhide, overwrite or delete records. Resolve the exact conflicting IDs privately with the owner; never bypass by changing a stable key or editing the registry to conceal drift. Removing a CSV row does not delete a bathroom. Retirement requires a separately reviewed moderation action; a later import will detect that visibility change as drift. Historical private bathrooms remain private even if their names coincide.

Test using **only** a new disposable catalogue instance and private state outside the checkout:

```sh
POC_INSTANCE=catalogue XDG_STATE_HOME=/tmp/bath-a52-state \
  nix develop .#backend --command python3 backend/catalogue_rehearsal.py
```

The rehearsal refuses a populated instance, never resets it and stops its containers afterwards. For a clean repeat, explicitly remove only this disposable instance's resources with `POC_INSTANCE=catalogue XDG_STATE_HOME=/tmp/bath-a52-state nix develop .#backend --command python3 backend/poc.py clean`. Never use the retained `fixtures` instance, development seeder, managed project or owner activity for catalogue rehearsals.

## Review tags

Edit `reviewTagSuggestions` in `lib/models/content_suggestions.dart`. The initial 40 tags are humorous Portuguese labels; their organizational categories do not appear in the UI. Keep a valid emoji and unique normalized label, within the existing 30-grapheme limit. Six suggestions are sampled once per review draft (or explicit refresh); search uses the complete approved and eligible personal/community pool. Selected/custom tags, duplicate prevention and validation remain independent. Changing this source never rewrites stored reviews or historical tags.

## Emoji and color suggestions

Edit `bathroomEmojiSuggestions` in the same file. Eight distinct suggestions are sampled once per bathroom draft or custom-tag dialog. **Outros emojis** refreshes suggestions without changing the selected emoji. Any valid single emoji grapheme remains available through the keyboard. Do **not** change/reorder `Bathroom.emojis`: historical fallback identities depend on it.

Edit the `(Portuguese name, RGB integer)` pairs in `bathroomColorSuggestions`. The 18 swatches wrap responsively and preserve arbitrary RGB, exact hex input, live identity preview and initial/explicit random colors. Colors are visual identity, with no rating meaning. Do not change legacy `Bathroom.accent` indices or reinterpret stored RGB values.

## Decorative collection progression

Edit the sorted `(minimum distinct discoveries, emoji, internal design title)` tuples in `discoveryProgression`. Retain a zero threshold and strictly increasing absolute counts. Only the emoji is displayed in the collection header. A bathroom is discovered after a visit; repeated visits count once. Catalogue size does not determine the emoji. This is decoration, without persisted levels, rewards, achievements or privileges.

## Android branding

Keep the original `assets/branding/app-icon.png` unchanged. Generate deterministic exports with:

```sh
nix develop .#branding --command python3 tool/generate_branding.py \
  --preview-dir /tmp/bath-branding-preview
```

The script uses ImageMagick from the pinned Nix flake, extracts the throne with a source-coordinate silhouette and preserves its crown. It removes the source's baked rounded tile/white corners, uses a continuous purple adaptive background and centers the foreground inside the adaptive safe area. A replacement source needs an explicit silhouette/scale review; do not apply the old outline blindly. Commit the derived Android density PNGs with the source, generator and XML resources. Generated Android resources are application source assets, not build artifacts. No new Flutter dependency is needed.

Inspect circular/rounded-square previews and the 48px legacy icon, then build/install the signed APK in place and inspect the actual launcher and native splash (both themes). Preserve `com.example.bath_royale`, existing certificate and version-code workflow; launcher label is **Bath Royale**. Never uninstall or clear application data for branding changes.

After edits run Dart formatting, strict analysis, all Flutter regressions, backend/tool unit checks and the disposable import rehearsal. Layout tests cover narrow/desktop widths, enlarged text, keyboard and both themes. Build unconfigured/distributable releases, run fixture/credential isolation scans on actual APKs, then separately build/install the private development target. See [A5.2 verification](backend/final-alpha-content.md).
