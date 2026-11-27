# A5.3 — Managed alpha deployment and release acceptance

Status on 2026-11-27: managed deployment and automated acceptance verified; owner physical acceptance and configured publication remain separate gates. `ALPHA_RELEASE_APPROVED=false`. No configured APK has been published. The restoration-blocker resumption used isolated infrastructure only, with no live Supabase request or mutation.

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

Repository variables contain public configuration only. The existing signing secret remains present and `ALPHA_RELEASE_APPROVED` stays explicitly **false**. CI retains validation and monotonically increasing `1000 + GITHUB_RUN_NUMBER` codes; unconfigured validation does not upload APK artifacts or publish development releases. Configured publication remains draft-first and uses the prepared [Portuguese release notes](../releases/alpha-notes.md) plus update/checksum instructions. No workflow was dispatched to publish this APK. A future approved workflow must use a fresh compatible code and reviewed commit; local builds do not prove hosted compilation success.

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

## Physical acceptance and publication gate

Automated installation proves package/signature/update compatibility, not the full device lifecycle. The owner will perform the remaining physical acceptance separately. Keep these items open:

- Confirm the official catalogue and independent account behavior without fictional selectors/content.
- Confirm login/current-password changes, complete app restart with restored session, and a **new saved recovery code**. The provisioning proof was consumed and cannot recover the account.
- Record a legitimate visit/favourite while offline, reconnect and verify it reached the account; distinguish opening a form from saving/submitting a record.
- Send an actual feedback message through the floating feedback control and confirm administrator access. This is app feedback, separate from a bathroom review.
- Verify in-place local data/environment retention. A second physical Android device was unavailable; do not claim it was tested. Automated independent accounts and isolated restart tests are separate evidence.

Then obtain explicit final owner publication approval before changing the gate or publishing the configured universal APK. Before public launch, replace the personal support contact everywhere and implement appropriate verified-email authentication/recovery. Deployment approval does not waive either gate.
