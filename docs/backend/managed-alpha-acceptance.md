# A5.3 — Managed alpha deployment and release acceptance

Status on 2026-11-27: **A5 initial alpha is complete**. Managed deployment, automated acceptance and owner-reported physical acceptance are complete; the authorized [alpha 1039](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1039) is published and independently verified. Second physical device testing remains pending. `ALPHA_RELEASE_APPROVED=false` again after this release. The restoration-blocker resumption used isolated infrastructure only, with no live Supabase request or mutation. See the final publication evidence below.

## Managed deployment evidence

The authenticated CLI/Management API identified the existing **Bath Royale Test** project, reference `eiitfxbmavmqafqwfxiy`, Frankfurt (`eu-central-1`), healthy and on the organization's **Free** plan. PostgreSQL was 17.12. Verified-TLS inspection found only migration `202611250001_core.sql`, whose checksum matched the immutable repository file; two known fictional accounts and the original four-bathroom rehearsal sample remained. Complete domain rows matched the historical verified export. Only Auth sign-in/update timestamps differed. No uncertain or owner-created domain activity was discarded.

Before upgrading, the operator held bounded SHARE locks on the preserved application/Auth identity/session tables, draining existing writes throughout the native export. Signup and API role grants were not persistently closed to take the backup. The explicit `--legacy-core` export requires the exact original ledger/checksum and exact core application table set. Its native schema/data/Auth export was encrypted for the owner-provided recipient, decrypted and checked, and restored independently before any managed migration. Source credentials and identities stayed outside Git and logs.

The ordered transactional plan applied migrations 002–017 after checking 001. Source-row guards and the protected moderation calls hid the explicitly identified legacy fictional bathrooms/reviews in the same transaction. The old moderator entitlement was revoked. Both historical fictional identities were reversibly banned through native Auth Admin and their sessions revoked; their hidden legacy records were preserved. Existing access-token issue times were already beyond their previous lifetime. No project reset, truncation, forced account erasure or fixture seeder was used.

The operator importer then completed a managed database dry run without permanent changes or conflicts, imported the exact **34** approved official entries, and passed an unchanged repeat. UUIDs, names, emojis, RGB values, registry associations and official classification match `content/official_bathrooms.csv`. No reviews, visits, tags, ratings or favourites were fabricated for these entries. Public feeds project current visibility, so hidden historical fictional content cannot be replayed.

## Auth, privacy and administrator

Effective managed Auth configuration was read back after applying the approved policy:

- Open email/password signup, confirmation disabled, minimum password eight characters; no invitation, allowlist or manual normal-account provisioning.
- Native `security_update_password_require_current_password=true`, refresh rotation enabled, ten-second reuse interval and access JWT lifetime 300 seconds.
- SQL Before User Created and Send Email hooks enabled. The former enforces the global 100-attempt daily/3,000-account ceilings; the latter blocks recovery/OTP through unverified email. Verification/OTP limits were 30 and token-refresh limit 150. Unused external providers, OAuth server, SAML and manual identity linking were disabled.
- **104 actual managed HTTP/API assertions passed:** registration/login, missing/wrong/correct current password, recovery-code replacement/one-time bound consumption and native administrative recovery, blocked email/OTP recovery, hook quota enforcement, RLS, independent accounts, private history/favourites, public anonymous reviews and historical-feed privacy, ordinary-account creation/moderation/admin denial, metadata escalation rejection, feedback permissions/idempotency, refresh rotation and logout.

The two self-registered disposable acceptance accounts were individually proven and erased through the protected domain procedure followed by native Auth deletion. Their temporary activity was removed before owner access. No test administrator or creator was provisioned.

The owner registered normally in the installed app and provided a recovery proof through a private local file. Bound SQL consumed that one-time proof and atomically granted administration and the separate creation entitlement to the returned exact UUID. Email was not used as identity evidence. Actual managed authenticated-role SQL checks exercised administrator feedback read/status, entitled creation, moderation and operator-only boundaries in a completely rolled-back transaction, exposing no synthetic bathroom. Those SQL checks are role simulation, not a claim of an owner HTTPS session.

The approved [manual operating policy](alpha-operations.md) is reflected in the app/privacy and prepared release notes: data until proven deletion, encrypted daily backups with rolling seven-day retention, reviewed feedback after 90 days, resolved support cases after 30 days and minimal erasure ledger through affected backup expiry. No scheduled backup, inbox cleanup or automated retention service is claimed. The operator must perform and record these duties.

## Final encrypted backup restoration blocker — resolved

The final postdeployment export contains all **21 preservation tables**, including Auth users/identities, the verified administrator/creator, official import registry, private activity, feedback, signup counters, recovery table, synchronization clock/records/changes/receipts/cursors and migration ledger. Empty tables are retained and verified too. Runtime sessions remain deliberately excluded from destination restoration under the existing policy, requiring fresh login; original native exports remain intact.

The first isolated restoration imported all rows successfully. Complete data and effective ACLs matched. Strict inventory comparison correctly stopped on precisely two constraint definitions:

- `app_private.alpha_feedback.alpha_feedback_app_version_check`
- `app_private.alpha_feedback.alpha_feedback_platform_version_check`

The source migration writes `length(...) BETWEEN 1 AND ... AND ...`. PostgreSQL stores the BETWEEN comparisons as a nested Boolean expression; `pg_dump` deparses comparisons whose reparsing flattens the surrounding AND. Bounds, patterns and data had not changed, but the restored catalog definitions differed from the source.

`cloud_transfer.restore_schema` reconstructs the original BETWEEN syntax only when both the complete sealed-source definition and exactly one complete quoted dump definition match the two reviewed migration-012 forms. Changed bounds or duplicate definitions fail closed. The adapted schema and compatibility decisions belong to the new destination evidence; **the encrypted archive, sealed source export, original schema/data and migration files are unchanged**. Preservation still compares all constraint definitions exactly; no new comparison normalization or skipped table was introduced.

The regression creates a new Unix-socket-only PostgreSQL cluster, demonstrates the original dump/restore mismatch, restores exact definitions and synthetic rows using the repair, and verifies rejection of invalid length/character/control-character inputs, changed limits and duplicate definitions.

A fresh extraction was decrypted from the original encrypted final backup and matched the original sealed export byte-for-byte. A never-used rootless `a53-fixed-final` target then passed `restore` and a separate `verify`: every complete row, schema definition, RLS flag/policy, table/function/column effective ACL, constraint and rolled-back foreign-key revalidation matched. PostgreSQL target 17.6 and Auth v2.198.0 remain independently pinned; platform roles/Auth migration versions are inventoried, not falsely claimed identical to managed infrastructure.

**86 further isolated restored-state assertions passed:** exact anonymous official catalogue over HTTP, idempotent import preserving rows/sequence, hidden fictional publication, private records/feedback, exact feed sequence/called state, retained receipt replay, private cursor continuation, transaction-ID clock collision handling and safe next watermark. Original passwords authenticated two explicitly known retired fictional identities with unchanged UUIDs after unbanning only their isolated copies. Native refresh rotation, source refresh-token rejection, private RLS/feedback denial and another process/service restart passed. The owner's password was neither requested nor reset. Login/refresh left application data unchanged. These are automated local checks, not physical-device testing.

The original failed target was not reused to manufacture a passing receipt. Private diagnostic/restoration evidence is encrypted; disposable targets and temporary decrypted copies are removed after verification. Original encrypted backups and original owner-only sealed exports remain preserved outside the checkout under the seven-day operating policy. Filesystem removal is not a claim of forensic media erasure. No live restoration or managed modification was performed during diagnosis or correction.

## APK and release preparation

The private managed-configured universal APK is `0.1.0-alpha.1038`, code **1038**, 61,974,654 bytes, SHA-256 `909a0d48cf241ad20c37d8468891ac90ae6f1779d3bfffa0e023313027569c54`. It uses ordinary `lib/main.dart`, the real managed HTTPS endpoint and public anon client key only, trusted system TLS, alpha policy and feedback. Actual APK scans exclude fixture account/encoded credential/selector material and local TLS shortcuts.

The original certificate fingerprint is `4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`; package remains `com.example.bath_royale`. Signature, exact version, non-debuggable universal ARM32/ARM64/x86_64 AOT payload and checksum were verified. `adb install -r` succeeded on SM A166B, retaining app ID 10419 and first-install time `2026-11-26 22:40:55`. No uninstall/data clear or development-namespace migration occurred. The private artifact is not a GitHub release.

At the deployment handover, repository variables contained public configuration only, the existing signing secret remained present and `ALPHA_RELEASE_APPROVED` was **false**. CI retains validation and monotonically increasing `1000 + GITHUB_RUN_NUMBER` codes; unconfigured validation does not upload APK artifacts or publish development releases. Configured publication is draft-first and uses the reviewed [Portuguese release notes](../releases/alpha-notes.md) plus update/checksum instructions. The private code-1038 APK itself was never uploaded. The subsequently authorized workflow uses a fresh compatible code and the reviewed commit; local builds do not prove hosted compilation success.

## Executed local release checks

On the final source state, **242 Flutter tests passed** with five opt-in placeholders skipped; **38 backend tests** and **14 release/tool tests passed**. Backend tests include two executed Unix-socket PostgreSQL regressions, not skipped placeholders. Strict Dart analysis passed with the existing reviewed Material-import baseline; Dart/Ruff formatting, Ruff lint, actionlint and Git whitespace checks passed. Linux and unconfigured Android release builds passed locally. The unchanged private configured APK was separately reverified for signing/version/universal AOT and fixture exclusion. No hosted CI success is inferred from these local checks.

Reproducible local checks:

```sh
flutter test --no-pub
dart run tool/check_analysis.dart
dart format --output=none --set-exit-if-changed lib test tool
python3 -m unittest discover -s tool -p 'test_*.py'
actionlint
nix develop .#backend --offline --no-write-lock-file --command \
  env PYTHONPATH=backend python3 -m unittest discover -s backend/tests
nix develop .#backend --offline --no-write-lock-file --command ruff check backend
nix develop .#backend --offline --no-write-lock-file --command ruff format --check backend
flutter build linux --release --no-pub
flutter build apk --release --no-pub
```

The managed API and private runtime scripts/receipts are retained only in encrypted operator evidence. Do not rerun tests that create or erase acceptance accounts on live data as a routine regression; use a fresh isolated restoration. `cloud_transfer.py restore` followed by `verify` is the reproducible source-preservation gate described in [transfer operations](cloud-transfer-tooling.md).

## Owner-reported physical acceptance

On 2026-11-27, the owner explicitly confirmed completion of the remaining physical acceptance tests and authorized initial-alpha publication. This is the owner's report for the installed managed build on the existing SM A166B, separate from operator-observed installation and automated API checks. The accepted checklist covers:

- Official catalogue and account behavior without fictional selectors/content.
- Login/current-password changes, complete app restart with restored session, and a new saved recovery code. The provisioning proof was consumed and cannot recover the account.
- A saved legitimate offline visit/favourite followed by reconnection and synchronization.
- Actual app feedback submission and administrator access, separate from a bathroom review.
- In-place local data/environment retention.

No new physical test was performed by the operator during publication. **Second physical device testing remains pending**, with the owner's authorization to proceed; independent-account API and isolated restart checks are not physical multi-device evidence. The fresh Actions APK has the same source, package and certificate and an increasing version code; it is independently inspected, not claimed newly installed or physically tested.

Before public launch, replace the personal support contact everywhere and implement appropriate verified-email authentication/recovery. Initial-alpha publication approval does not waive either mandatory gate.

## Final publication verification — 2026-11-27

The preceding [CI run 45963682052](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45963682052) completed successfully for `6bb49a117d909c11084001f5ca6dfee70a30b018`. Publication uses this unchanged, verified source.

Fresh verified-TLS SQL inventory used read-only transactions. It confirmed 34 exact official registry/domain entries, four hidden historical bathrooms, two banned historical fictional accounts and one active owner account with both administration and creation entitlement. Anonymous HTTPS `public_catalogue` returned precisely the approved UUID/name/emoji/RGB/classification set; `public_reviews` returned no reviews. Anonymous direct-table access returned no rows under the existing RPC-only catalogue policy. Public Auth settings still permit registration without mandatory email confirmation. No live data, privileges, Auth configuration or schema was changed during publication verification; no fixtures, cleanup or reset ran.

Both original encrypted backup hashes and the encrypted restoration-evidence hash were rechecked. All three archives authenticated and decrypted in memory; no temporary plaintext files were created. Every sealed export file, including its original manifest, matched the encrypted archive byte-for-byte; the separately archived pre-maintenance/current Auth configuration snapshots were also validated. The previously successful fresh isolated full restoration and 86 runtime/protocol assertions remain the restoration evidence; no new restoration is falsely claimed. Backups are from this same UTC day and remain within the seven-day retention period. Original archives and sealed exports remain unchanged. The operator must continue the daily/manual duties, separate identity custody and expiry/erasure tracking in [alpha operations](alpha-operations.md); no scheduler or automated inbox maintenance has been introduced.

The Portuguese release notes and actual in-app privacy notice were reviewed together: open registration, unverified email, recovery codes, public anonymous reviews, private visits/favourites/feedback, manual daily encrypted backups/seven-day retention, reviewed feedback 90 days, resolved support 30 days, proven deletion and offline/backup delay. The personal support contact is explicitly limited to this initial alpha.

The owner-approved gate was enabled and [workflow dispatch 45965320805](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45965320805) completed **successfully**, including both `verify-and-build` and `prerelease`, against the exact source above. The workflow repeated formatting, tooling tests, strict analysis and the Flutter suite before the configured release build, fixture scan, signature/version verification, artifact upload and byte-checked draft publication. No workflow or application source was changed for this release.

Published at `2026-11-27T08:29:12Z`: [Bath Royale — Alfa 1039](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1039), a non-draft pre-release, not the latest stable release. The lightweight `alpha-1039` tag points exactly to `6bb49a117d909c11084001f5ca6dfee70a30b018`. Both public assets were then downloaded anonymously without GitHub credentials:

- [bath-royale.apk](https://github.com/Samuel-Fortunato/bath_royale/releases/download/alpha-1039/bath-royale.apk), **61,974,654 bytes**, `0.1.0-alpha.1039` / code **1039**, greater than installed code 1038.
- [SHA256SUMS](https://github.com/Samuel-Fortunato/bath_royale/releases/download/alpha-1039/SHA256SUMS), independently matching APK SHA-256 **`8f08897043cbb03849165f0899e2e14fe18750793ec32502b70f7272c9a09a5f`**.

The downloaded APK passed `tool/verify_preview.py`: original certificate `4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`, package `com.example.bath_royale`, exact version, non-debuggable universal ARM32/ARM64/x86_64 AOT and no debug Dart kernel. Each architecture's actual AOT payload contains the expected managed HTTPS origin and public publishable client key. Payload scans exclude known fixture identities, the private fixture credential payload/selector, local TLS endpoints/certificate material and the actual database credential. The public release body contains the exact reviewed Portuguese alpha notes. No privileged credential or encryption identity was included in release assets, reports or Git.

After the configured build passed, the gate was reset and read back as **`ALPHA_RELEASE_APPROVED=false`**. This does not withdraw the published APK; it prevents the subsequent documentation push from publishing another build. Future configured releases require separate operator approval and a fresh increasing workflow version. The owner installs this APK as an update, never by uninstalling or clearing data; no new installation or second-device test is claimed during publication. See [phone installation instructions](../android-previews.md#download-and-install-from-a-phone).

The documentation-only completion was additionally checked with 14 tooling tests, actionlint, local link validation and Git whitespace checks. Source and backup evidence remain as described above; no new managed test account or fabricated activity was created.
