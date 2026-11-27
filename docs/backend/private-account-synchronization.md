# A2 — Private account synchronization

Current behavior: [A3 community alpha](community-alpha.md) supersedes the earlier optional enable/pause modes and adds anonymous catalogue browsing. Account storage requires clear initial acceptance and then synchronizes automatically. Public publication remains a separate explicit action; archived guests/examples stay excluded. The A1/A2 evidence below is historical.


A2 is the approved continuation of A1/A1.1. The application now connects the existing transactional SQLite outbox, Auth session generation, authenticated HTTP adapter and server receipt/CAS/pull protocol. This does not enable a public catalogue, guest association, public profiles or publication. The managed project is not a deployment target for this work.

## Consent and account boundaries

Profile → **Sincronização privada** explains the uploaded entities, existing-account backfill, offline behavior and the distinction from publication. **Agora não** sends nothing. **Ativar e enviar dados privados** commits consent version 1 and eligible backfill atomically in that account's SQLite file. Consent is specific to the environment, subject and device store. Another device must consent independently. Local actions can queue before consent, but neither the controller nor its coordinator may transfer without it.

Only genuine `user_created` account records are backfilled. Existing remote records can be edited; child ownership remains the signed-in account. Demo and unclassified legacy provenance never qualifies. Original guest files remain archived and are never opened, imported, associated or scanned by A2. A new account remains empty. Local theme settings are device preferences and are not uploaded.

Pausing keeps queued changes and local records and stops continuation of an in-flight synchronization run. A request already committed by the server cannot be recalled; its immutable operation ID makes a later retry safe. Pausing does not erase remote copies. Logout retains isolated account files and consent. It never exposes those files to another account. Secure credential persistence and offline identity restoration remain the existing Auth implementation.

## Application integration

`AccountStateScope.device` opens the existing namespace, restores its account AppState and attaches `PrivateSyncController`. It injects `HttpRemoteDataSource` with the current access token and publishable API key; no refresh token enters that adapter. The existing `BathroomRepository` commits the domain mutation and outbox command in one SQLite transaction.

Synchronization runs on consent, local state events, session changes, foreground resume or **Sincronizar agora**. Uploads and pulls are bounded. A full page/remaining ready commands schedule another short foreground pass. Transport failures use durable jittered exponential backoff and one-shot timers while work/recovery remains; expired offline authentication has separate retry pacing so ready outbox rows cannot cause rapid renewal loops; there is no idle polling, background service, Realtime subscription or new dependency. Reconnecting a foreground device with pending work resumes on its retry timer, an action or manual retry; foreground resume also checks for changes. Remote edits while an otherwise idle foreground app stays open appear on the next such event.

The coordinator rechecks account namespace, Auth generation, expiry, cancellation epoch and consent after every network await. A 401 pauses that generation. The application attempts one serialized forced SDK renewal; it only automatically retries after an actual replacement token. Failed renewal retains local input and provides account/retry feedback. Revocation follows the existing fail-closed credential-restoration policy. Signing in again to the original account restores its durable outbox. Open editor drafts and failed local commits continue to block account replacement.

## Remote cache and recovery

The existing `remote_records` cache and checkpoints remain separate from domain rows. `AccountProjection` materializes canonical account snapshots transactionally, in bathroom/visit/review/favourite order, without enqueuing them. Unresolved local operations protect their targets and referenced parent identities. Historical pull pages cannot overwrite a newer acknowledged local revision; terminal tombstones retain their actual revision so explicit recovery still applies removals. An open editor, removal-confirmation dialog or failed local commit defers synchronization until it closes or storage recovers. A network response received while such work is open cannot advance its unseen revision/checkpoint. Recovery retries retain the original causal predecessors/base, so an unseen concurrent change still conflicts. Model validation happens before projection commits. Local UI state reloads only after success.

SQLite v6 → v7 preserves domain records, IDs, timestamps, outbox/dependencies, revisions, conflicts, checkpoints and settings. It adds consent and a recovery archive. Account bathroom name uniqueness is a UI rule, not an identity constraint: two devices can independently create distinct IDs with the same name without breaking convergence. The account-only table rebuild follows SQLite's foreign-key-safe procedure; guest tables retain their prior constraints. Normal restarts never reset storage.

Concurrent edits use server revisions and causal predecessor receipts, never device clocks. A remote cache advance cannot silently become the base of an unresolved local edit. Duplicate submissions and lost acknowledgments retain the original operation ID. Visit/review compound writes and deletions retain their shared-revision protocol. Optimistic local deletion does not manufacture a terminal server tombstone, so a rejected stale removal can be restored from the account.

The synchronization page shows pending/running/error status and each rejected/conflicting edit. It retains exact original payloads. The user can explicitly resend against the displayed conflicting revision, correct a rejected bathroom name/comment without truncation, or use the account version and archive that whole dependent branch. Deleted remote identities cannot be resurrected. Archived input stays selectable on that device, including original comments/tags; it is never automatically resubmitted. If no remote version exists, the archived local record remains available locally. New UUIDs distinguish deliberate resubmissions from immutable original receipts.

**Recarregar dados da conta** starts bounded full replay if a checkpoint is unavailable. It preserves the cache, consent, local records, outbox and archives. Known expired server cursors already replay safely through the original protocol. There is no automatic last-writer-wins merge or destructive error recovery.

## Server privacy and text validation

Additive migrations change private owner foreign keys to `auth.users`, removing the requirement for a public `profiles` row. Sync-created bathrooms carry a server-assigned `account_private` marker, cannot become approved/verified and are absent even from another account's moderator view. Existing historical catalogue/proposal fixtures retain their previous behavior; A2 adds no publication path. Visits/favourites can reference an owned private bathroom. Reviews stay unpublished. RLS, narrow RPC grants, server-derived ownership, exact private-feed subjects and public projection allowlists remain enforced.

The server counts extended graphemes using the exact category ranges and forward automaton from locked `characters` 1.4.1. `tool/generate_grapheme_sql.dart` regenerates the replacement validator; third-party notices are retained in `backend/licenses`. The real suite compares 1,093 locked Unicode segmentation vectors against Dart. Names, comments, labels and single-emoji validation now accept the same combining accents and long emoji clusters as the client. There is no normalization/truncation of submitted content. The editor explicitly rejects NUL input, which PostgreSQL text cannot represent, while preserving the draft for correction. Historical local records are not rewritten by this validation change.

The validator replacement and permission follow-ups are additive: local migrations already exercised during this task retain their checksums. No previously applied foundation migration is rewritten.

## Portability and verification

The logical export allowlist now includes `sync_clock`, `sync_records`, `sync_changes`, `sync_receipts` and `sync_cursors`. Transfer adaptation explicitly retains `sync_changes_position_seq` while continuing to reject unknown sequences. `sync_revision()` also requires a transaction-local marker, preventing a restored source xid from accidentally reusing a revision in a destination transaction with the same xid.

`backend/sync_portability.py`, called by the isolated sync runner, exports using the real allowlist, restores into a fresh temporary database in that disposable container, compares every preserved row and the sequence, replays an original receipt, resumes a scoped cursor and reproduces an xid collision. It opens no new listeners and removes only its named temporary database. The earlier managed export evidence is not reused as proof of A2 and the managed project is never contacted.

Run the complete real suite with `POC_INSTANCE=sync nix develop .#backend --offline --no-write-lock-file --command python3 backend/synchronization.py`. It includes the authorization matrix, profile-free accounts, anonymous/other-account exact-row and feed denial, two independent device stores, offline reconnection, conflict recovery, stale deletion, consent, v6 upgrade and restart convergence. Separate-process fixtures run under Flutter because the observable Auth boundary uses Flutter foundation.

See [ROADMAP](../../ROADMAP.md) for executed counts/builds and [the USB device procedure](../android-auth-device-testing.md) for physical acceptance. Physical Keystore, password-manager and subjective UI behavior are distinct from automated evidence.

## Remaining boundaries

A3 public identity/catalogue/publication is unstarted. Guest association remains prohibited. Remote private-alpha registration restriction, account erasure, retention/compaction, real-user non-destructive migration policy, hosting/production email and operational capacity remain release decisions before admitting real users. The existing coarse server writer lock and retained append-only protocol history remain intentional prototype limitations. This implementation does not select irreversible publication, moderation, deletion-retention or hosting policy.
