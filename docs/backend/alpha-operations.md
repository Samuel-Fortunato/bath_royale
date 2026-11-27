# Initial alpha operator responsibilities

The owner approved this policy for A5.3 on 2026-11-27. The owner operates the existing Supabase Free project and personal support inbox during the initial alpha. These are manual duties, not scheduled services. Do not admit alpha users if the operator cannot carry them out. Deployment/verification evidence is recorded separately in [managed acceptance](managed-alpha-acceptance.md).

| Data | Approved retention and responsibility |
| --- | --- |
| Account/domain data | Keep until a deletion request proves control of the exact account. Follow the protected recovery/erasure procedure in [release preparation](alpha-release-preparation.md#private-recovery-and-deletion). |
| Backups | Encrypt every daily backup, verify it, keep a rolling seven days and remove expired copies from every operator-controlled location. Keep the decryption identity separately, including a recoverable copy outside this computer. |
| Reviewed feedback | Remove after 90 days from recorded review. Never infer review time from submission time. |
| Resolved support cases | Remove case content and attachments 30 days after recorded resolution. Keep account proofs/passwords/codes out of operational summaries. |
| Erasure ledger | Only account UUID and erasure time; keep until every affected backup has expired. Reapply erasures to restored data before reopening access. |

Before public launch, replace the personal contact across app, privacy, docs and release materials, and implement appropriate verified-email authentication/recovery. Initial-alpha email labels and `email_confirmed_at` do not prove mailbox ownership. No invitations, allowlist or manual user provisioning are required.

## Daily backup

Use the pinned `nix develop .#backend` shell (`age`, Supabase CLI and PostgreSQL tools). Keep credentials and plaintext work in owner-only directories outside Git; use `umask 077`. Set `BACKUP_RECIPIENT` to the approved public recipient and `BACKUP_IDENTITY` to the protected identity file outside Git. Keep their operator-specific configuration outside this repository. Never print, commit or include the private identity in an archive.

Choose fresh paths for each run. Quiesce application and Auth writers for the complete export: `--quiesced` alone does not stop them. The A5.3 operator uses a separate verified-TLS transaction with SHARE locks on the preserved application tables and Auth identity/session tables, a 20-second lock timeout and a bounded idle timeout. Wait for locks before exporting; abort if they cannot be obtained. Release using ROLLBACK in a finally block. Do not change access grants merely to take a backup. Inventory again if the schema changes. Native exports use multiple snapshots, so the lock must remain alive throughout export and before/after comparisons.

Generate the current lock statement offline, then execute it in a **separate interactive private psql session** using the verified connection environment. Keep that session open while the second terminal exports. For the historical core-only backup use `LEGACY_CORE` instead of `migration.TABLES`; never silently omit a missing current table.

```sh
PYTHONPATH=backend python3 - <<'PYLOCK'
import migration
from cloud_transfer import SESSIONS
print("BEGIN; SET lock_timeout='20s'; SET idle_in_transaction_session_timeout='180s';")
print("LOCK TABLE " + ",".join(migration.TABLES + sorted(SESSIONS)) + " IN SHARE MODE;")
print("SELECT pg_backend_pid(), pg_current_xact_id();")
PYLOCK
```

Record the returned backend/transaction identifiers. After export, check they are unchanged in the lock session before `ROLLBACK`. If the session disconnected or its timeout fired, reject that backup attempt and repeat with a fresh bundle after diagnosis. Running a lock file with `psql -f` and letting psql exit does **not** retain the locks for another command.

```sh
# Paths/reference are private operator selections; no credentials in arguments.
python3 backend/cloud_transfer.py export --source-state "$SOURCE_STATE" \
  --project "$PROJECT_REF" --bundle "$BUNDLE" --quiesced
python3 backend/cloud_transfer.py verify --bundle "$BUNDLE"
tar -C "$(dirname "$BUNDLE")" -cf - "$(basename "$BUNDLE")" |
  age -r "$BACKUP_RECIPIENT" \
    -o "$ENCRYPTED_ARCHIVE"
sha256sum "$ENCRYPTED_ARCHIVE" > "$ENCRYPTED_ARCHIVE.sha256"
sha256sum -c "$ENCRYPTED_ARCHIVE.sha256"
```

Run pipelines with `set -o pipefail`. Never overwrite a backup. A native pre-upgrade backup of the exact unchanged core-only schema uses the explicit `--legacy-core` export option. It requires the exact core checksum/ledger and exact core application table set; it does not mark later migrations applied or invent missing data. Restore reads the manifest scope and accepts only the complete current scope or that exact nine-table legacy scope. Unknown populated sections still fail. Keep the original native dumps unchanged.

Decrypt into a fresh private work directory, inspect archive member paths, extract only the trusted archive, and run `verify` on the extracted bundle. Then restore into a new isolated target:

```sh
age -d -i "$BACKUP_IDENTITY" \
  -o "$PRIVATE_TAR" "$ENCRYPTED_ARCHIVE"
tar -tf "$PRIVATE_TAR"
# Extract the inspected trusted archive into a fresh 0700 directory.
tar -xf "$PRIVATE_TAR" -C "$PRIVATE_RESTORE_WORK"
python3 backend/cloud_transfer.py restore --bundle "$DECRYPTED_BUNDLE" \
  --destination "$FRESH_NAME" --disposable --auth-port "$UNUSED_AUTH_PORT" \
  --rest-port "$UNUSED_REST_PORT"
python3 backend/cloud_transfer.py verify --bundle "$DECRYPTED_BUNDLE" \
  --destination "$FRESH_NAME"
```

The restore verifies complete account/application rows, schema, RLS, grants, constraints and foreign keys. Refresh sessions are excluded intentionally; restored users sign in again. Never run fixtures on managed data or restore over the live project. Stop the isolated target after verification. Record archive checksum, creation/expiry time, successful decryption and isolated restoration in the private operations journal. Remove only the plaintext work created for this completed run after verification; never remove credential directories or historical owner evidence as cleanup.

Review expired archive/checksum pairs daily and remove only those whose recorded creation time is at least seven days old. Include copied archives and restored sensitive targets in the inventory. A missed backup must be recorded and corrected immediately; do not invent a successful daily run or silently retain old backups indefinitely. Keep the minimal erasure ledger until all affected copies actually expire. There is no installed cron job or claimed automatic pruning.

## Feedback and support maintenance

Migration 012 records submission time but not review time. When reviewing a report, record its UUID and actual review timestamp in a private 0600 JSON journal outside Git. Reset that observation if a report returns to `new`; do not backdate unknown review times. The journal contains only entries such as `{"id":"<report-uuid>","reviewed_at":"<ISO-8601 UTC timestamp>"}`. Review/resolution remains in the existing administrator UI.

```sh
python3 backend/alpha_retention.py --journal "$PRIVATE_REVIEW_DATES" \
  --output "$PRIVATE_DRY_RUN_SQL"
# Execute via the private verified-TLS psql environment, ON_ERROR_STOP enabled:
psql -X -f "$PRIVATE_DRY_RUN_SQL"
# Review the count and backup before generating the separate write plan:
python3 backend/alpha_retention.py --journal "$PRIVATE_REVIEW_DATES" \
  --output "$PRIVATE_APPLY_SQL" --apply
psql -X -f "$PRIVATE_APPLY_SQL"
```

The default plan counts only and rolls back. Apply rechecks that each explicit UUID is still reviewed/resolved, was submitted before its recorded review, and its review was at least 90 days ago; it serializes with feedback submissions. New reports and unknown review dates are retained. Inspect returned IDs privately and remove only those entries from the journal after commit. No public cleanup RPC is exposed.

Keep support cases in a separate private store with a case reference and resolution timestamp. Each day, list resolved cases whose timestamp is at least 30 days old, check there is no active recovery/deletion action, then delete that exact case's messages, proof, attachments and local copies from the inbox/store. Record only completion/counts in the operations journal. The inbox provider's trash/retention must also be handled; deleting a local case file alone is insufficient. Unknown/unresolved cases remain until individually resolved. Keep the erasure ledger separately so case cleanup cannot erase an outstanding backup-erasure obligation. No automated inbox access or deletion is implemented.
