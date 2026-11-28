# Owner administration protocol (A7.2)

`backend/administration.py` is a versioned operator subprocess interface, independent
of the private manager. It installs no schema objects/public RPCs, starts no server,
and never migrates, provisions or resets a selected target. Existing catalogue
rules, moderator/creator/feedback RPCs, guards, constraints and sync capture remain
authoritative. The private owner handbook contains daily management workflows and
credential/recovery custody; do not put private operational state here.

Run with the pinned `nix develop .#backend` shell. JSON requests arrive on stdin;
JSON responses and safe categorized errors leave stdout. Stderr/SQL diagnostics
are captured, never forwarded. Protocol version is `1`. Every invocation requires
`--environment managed|development` and a corresponding explicit target:

- `managed`: `--state-directory /private/transient/stage`, validated by `cloud.py`.
  Uses its fixed project/session-pooler guard and verify-full TLS. No inherited
  PG defaults or legacy state fallback. The stage must contain owner-only
  connection JSON and the public API/CA inputs. Values never appear in argv.
- `development`: `--development-container broyale-admin-<16 lowercase hex>-db`.
  Requires the matching `io.broyale.admin.disposable` label, rootless mode, no
  privileged mode or host ports; plans bind the full container ID. Existing PoC,
  legacy and ordinary development instance names are rejected.
- `tags.builtins` reads only the checked-out Dart suggestion constant and requires
  no database resource. It reports application-source provenance rather than
  asserting which APK any device has installed.

Example stdin (no credentials):

```json
{"version":1,"operation":"db.stats","args":{}}
```

Read operations: `db.status`, `db.stats`, `catalogue.list`, `catalogue.inspect`,
`catalogue.validate`, `users.list`, `users.inspect`, `users.creators`,
`users.moderators`, `tags.builtins`, `tags.observed`, `feedback.list`,
`feedback.inspect`, `reports.list`, `reports.inspect`. Lists accept integer
`limit` (1–200, default 50) and nonnegative `offset`. Filters are strict enums.
Account and report projections exclude credentials and reporter identity;
feedback text is available only on explicit UUID inspection. Account activity
counts/sign-in history/ban state have distinct meanings; no engagement estimate.

Mutation operations: `catalogue.apply` (CSV importer), `catalogue.update`
(community appearance), `catalogue.hide`, `catalogue.restore`, `catalogue.remove`,
`users.grant`, `users.revoke`, `feedback.review`, `reports.hide`, `reports.restore`.
Except the privileged operator CSV importer, mutations select an existing
non-banned moderator through `args.actor`. Accounts/records are selected by UUID.
Creator changes prove a unique locked mapping from that UUID before calling the
existing label-based permission RPC; labels are not ownership proof.

Without `plan`, a mutation request returns a read-only preview, baseline digest,
exact target/arguments, application/CSV bindings and a 15-minute expiry. To apply,
supply the entire previous `plan`, the same operation/args and `confirmed:true`.
The offline `--environment managed --verify-backup PATH --project REF` adapter
reuses sealed-bundle verification to require the exact managed project, complete
current scope and current migration checksums without opening a database.
The private manager additionally enforces its protected plan digest, exact
confirmation token, backup/recovery prerequisites and minimal operational receipts
for every service/TUI caller. This operator tool assumes privileged database
credentials and is not a client authorization endpoint or standalone custody UI.

Apply takes the domain clock-first lock, feedback advisory lock and the inspected
table locks; it checks the ledger/checksums, baseline, expiry and exact preview
inside that same transaction. Unrelated domain/Auth changes can invalidate a plan.
The importer runs inside the outer guarded transaction, retaining its own identity,
name and full applied-content checks. Runtime visibility is preserved on reimport;
hide/restore changes the official registry baseline atomically with the live row.
Do not edit official appearance outside the CSV/importer.

Bathroom inspection includes domain counts, links, reports, registry, sync history,
receipts/dependent payloads and actual FK definitions. Permanent deletion only
accepts an unreferenced non-private community bathroom, with the exact known
non-cascading FK layout. It retains synchronization history and ordinary trigger
removal markers. Official retirement requires a future explicit registry/CSV
protocol; omission from the CSV never deletes. No trigger/constraint bypass is used.

Tag observations aggregate JSON objects already embedded in reviews. Current APK
suggestions are marked by label equivalence, without invented provenance. Variant
counts are computed across the full aggregation before pagination. No persistent
tag entity, historical rewrite or taxonomy migration is introduced. Wider tag
moderation needs an owner-approved versioned representation and compatible client
command/receipt/synchronization behavior first.

Feedback status uses the existing moderator RPC. Its private UUID/review-date
journal remains in the `alpha_retention.py` format; the manager centralizes and
imports that journal without overwriting conflicting timestamps. Newly reviewed
dates are recorded after commit, reopened dates invalidated before mutation;
crashes can delay retention, not accelerate it. Existing external administrator
changes still require the approved reset-on-new procedure in
[alpha operations](alpha-operations.md). No retention deletion/scheduling,
account erasure, recovery reset, banning or moderator-membership write is added.
Those remain the approved [private procedures](alpha-release-preparation.md).

Verification:

```sh
nix develop .#backend --no-write-lock-file --command ruff check backend
nix develop .#backend --no-write-lock-file --command ruff format --check backend
nix develop .#backend --no-write-lock-file --command env PYTHONPATH=backend python -m unittest discover -s backend/tests -v
nix develop .#backend --no-write-lock-file --command python backend/administration_rehearsal.py
```

The rehearsal creates one random no-network/no-host-port rootless PostgreSQL
container from the existing pinned image, applies current migrations, uses fictional
accounts/content and removes only that new target's ID/anonymous volumes/private
bootstrap file. No Auth/API service is started; the SQL-only fixture supplies the
`banned_until` compatibility column normally added on native Auth startup.
It checks importer corrections/omissions, registry drift, visibility feeds,
reference/unknown-cascade rejection, tombstones, actual lock contention/concurrent
writers, stale/rebound plans, permissions and feedback/report privacy. No managed
mutation or APK publication is involved. The private manager has a separate
end-to-end CLI rehearsal using this fixture; public tests never depend on it.
