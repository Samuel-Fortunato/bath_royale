# Managed export and fresh self-hosted restore tooling

`backend/cloud_transfer.py` extracts the Python execution scripts retained in the
private Phase 2.1C evidence bundle. The end-to-end rehearsal passed at **9b634c9**;
[its measurements, identities, compatibility findings and assertion counts](cloud-migration.md)
remain historical evidence. This refactoring has **offline** regression coverage
and a read-only comparison against the original private adaptations. It has not
been run against managed or local databases end to end. Do not attribute the
previous 231/226 assertions or timings to this new command.

This remains the reduced fictional-data PostgreSQL/Auth/PostgREST scope of 2.1C.
Storage, MFA population, production migrations, ARM and Phase 2.2 remain outside
scope. No fixture reset, cleanup, automatic retry, volume deletion, source Auth
login or source database write is performed by these commands.

## Environment and private inputs

Use the existing lock and backend shell:

```sh
nix develop .#backend --offline --no-write-lock-file
python3 backend/cloud_transfer.py --help
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -p 'test_*.py'
ruff check backend
ruff format --check backend
```

Export requires locked Supabase CLI **2.111.0** and host `pg_dump` **17.12**. Restore
reuses the digest-pinned Compose stack and rootless Podman lifecycle from `poc.py`,
with independently generated runtime passwords/JWT secrets and loopback-only
Auth/API ports. The database has no host port. No global service or configuration
change is needed. Component/lock hashes are recorded; restore refuses changed
Compose pins. A pin/schema change requires explicit compatibility review.

Keep all state, bundles, account files and session evidence **outside the checkout**.
Use directories owned by the current user with mode 0700 and regular files with
mode 0600. Bundles contain full Auth rows/password hashes and private content;
permissions and checksums do not encrypt them. Never attach them to commits,
issues, CI artifacts or logs. The tool prints pass/fail summaries and suppresses
SQL/subprocess diagnostics. A failed operation retains state for private inspection.

Source state contains `connection.json` (`database_url`), `api.json` (`url`,
`publishable_key`) and the project CA `root.crt`, using the existing preflight
formats. Supply the project reference explicitly. The reviewed guard requires a
matching HTTPS API project and PostgreSQL session pooler user/host/port/database.
It ignores URL query overrides, clears inherited libpq variables and enforces
`sslmode=verify-full`. Passwords travel through libpq environment variables,
never real credential-bearing command arguments. Export does not require signup
or email confirmation settings and does not call the Auth API.

## Independent operations

The following commands are **usage examples**, not authorization to repeat the
live rehearsal. Set the shell variables to privately selected paths/reference;
do not put credential values in shell history. Create a new 0700 bundle parent
outside Git first. Quiesce all managed fixture writers before export and keep
them quiescent through export/preservation. `--quiesced` records the operator's
acknowledgement; it is not a production maintenance lock. Separate role/schema/data
exports do not share a database snapshot. Before/after complete application/Auth
identity row comparison detects changes but cannot exclude transient writers.

```sh
python3 backend/cloud_transfer.py export \
  --source-state "$SOURCE_STATE" --project "$PROJECT_REF" \
  --bundle "$BUNDLE" --quiesced

# Offline only: no network, database or container calls.
python3 backend/cloud_transfer.py verify --bundle "$BUNDLE"

# A new name and two unused unprivileged ports must be explicitly selected.
python3 backend/cloud_transfer.py restore --bundle "$BUNDLE" \
  --destination "$NEW_DESTINATION" --disposable \
  --auth-port "$AUTH_PORT" --rest-port "$REST_PORT"

# Before any destination login/fixture changes; DB must still be running.
python3 backend/cloud_transfer.py verify --bundle "$BUNDLE" \
  --destination "$NEW_DESTINATION"
```

Export invokes the same CLI `db dump --db-url <placeholder> --dry-run` variants:
`--role-only`, schema, and `--data-only --use-copy`. Only generated `export PG...`
lines are removed. All remaining CLI `pg_dump`/`sed` filtering runs through Bash
with verified libpq credentials and fail-fast pipeline handling. It never
substitutes the local rehearsal's table allowlist for CLI platform filtering.
Original exports and generated scripts are immutable; private before rows,
canonical inventory, effective ACLs, column types and component hashes accompany
them. A format-versioned manifest checks completeness, owner/mode, byte sizes and
SHA-256 for every file. This is integrity checking, not proof of trusted provenance;
restore only bundles from a trusted export. Historical evidence bundles have a
different layout and are deliberately not consumed or modified by this tool.

Destination names use the separate `bath-royale-migration-<name>` namespace,
including private state under `${XDG_STATE_HOME:-~/.local/state}`. They cannot
select any of the three preserved `bath-royale-poc*` installations. Restore refuses
**all** existing destination state, containers, volumes or networks, even if they
are labelled disposable. Listing/daemon failures are errors, never proof of absence.
The explicit `--disposable` acknowledgement applies only to the newly created
target. State is reserved before bootstrap; interrupted/failed restores cannot be
reused automatically. Select a different fresh name after private diagnosis.
Concurrent operations against one target or bundle are unsupported.

The new target bootstraps its own Auth schema; Auth/API stop before import. Roles,
schema, adapted COPY data and ACL reconciliation run in **one** `ON_ERROR_STOP`
transaction. A failure rolls back the import; bootstrap remains for inspection.
Original source passwords, signing secrets, sessions and Auth migration state are
not used as runtime configuration. Complete `auth.users` and `auth.identities`
rows, including password hashes, are imported as data.

Compatibility policy is explicit and deliberately narrow:

- Exclude `auth.sessions`, `auth.refresh_tokens`, `auth.mfa_amr_claims` and only
  their known refresh-token sequence reset, requiring fresh authentication.
- Omit only empty `auth.custom_oauth_providers` and the nine Storage tables named
  in `EMPTY_OMISSIONS`. Populated unsupported sections fail. Other empty sections
  need matching target column names/types. New sequence resets, malformed,
  duplicate, truncated or missing required COPY sections fail.
- Populated retained sections must belong to the nine preservation tables in
  `migration.TABLES`. New populated Auth/application features require a reviewed
  policy and preservation scope extension rather than silent acceptance.
- Omit exactly the managed Realtime `log_min_messages` parameter grant. Other
  roles SQL is unchanged; an unexpected absent role fails transactionally.
- Revoke target effective table/function/schema and separate column grants, then
  replay source privileges and grant options. Expand implicit defaults, including
  PUBLIC function EXECUTE. Do not assume target creator default privileges match.
  Effective privileges are compared; identical grantor identities are not claimed.

Adapted SQL, compatibility decisions, complete after rows and target inventory stay
in the new private destination state with their own checked manifest; the sealed
export is unchanged. Verification compares full
identity/application rows (UUIDs, hashes, relationships, text, timestamps), the
application schemas/definitions/RLS/policies/constraints/table and column grants,
and effective table/function/schema/column ACLs. Deparsing uses an empty search
path, retaining the existing narrowly documented CHECK equivalence handling.
Foreign keys are dropped/re-added inside **rolled-back local transactions** to
check actual rows. Therefore destination verification requires local DDL privileges;
it is not purely read-only SQL. Platform roles/memberships, extension versions,
server version and Auth migration history are inventoried without claiming equality.

## Optional runtime preservation checks

Exact row verification must happen **before** login because Auth updates login
metadata. A separately opted-in mode then exercises the historical original-password,
UUID, refresh, unexpired source JWT/refresh rejection and independent restart checks:

```sh
python3 backend/cloud_transfer.py verify --bundle "$BUNDLE" \
  --destination "$NEW_DESTINATION" --runtime \
  --accounts "$PRIVATE_ACCOUNTS" --source-sessions "$PRIVATE_SOURCE_SESSIONS"
```

`accounts` uses the existing private A/B fictional account format. `source-sessions`
is a private JSON list of corresponding already obtained managed token responses
(`user.id`, `access_token`, `refresh_token`) in account order. The caller obtains
these only as part of an independently authorized rehearsal; this command never
logs into the source. Source access tokens must still be unexpired. These inputs
are not included in Git or copied to the target as signing/runtime credentials.
The target is bound to the export manifest by its private `transfer.json` receipt.

This mode starts target Auth/API and deliberately writes local login/session state,
then restarts the independent target and stops it in a `finally` block. It does
not run the destructive authorization fixture matrix. It cannot be repeated as an
exact pre-login row comparison after Auth metadata has changed. For subsequent
operational checks use the private target lifecycle deliberately; never run
`cloud_rehearsal.py`, `migration.py` or a fixture test to inspect retained data.
The historical full authorization matrix remains verified only at **9b634c9**.

## Refactoring validation (2026-11-26)

- Ruff lint/format and **25 Python tests** pass. Tests use synthetic content and
  mocked command boundaries; one test creates a temporary PostgreSQL cluster with
  a private Unix socket and no TCP listener, checks effective ACL reconciliation
  (including implicit function defaults, column grants and grant options), and
  demonstrates `ON_ERROR_STOP` rollback. It stops/removes only that temporary
  synthetic cluster. No existing database/environment is used.
- A separate read-only in-memory check against the retained private bundle found
  identical adapted COPY SQL and the same exact Realtime grant omission. It did
  not write or reseal historical evidence and did not connect to a database.
- Dart formatting, **105 Flutter tests**, Linux debug and Android debug builds
  pass. Current strict Flutter analysis exits 1 on **26 informational Material
  import deprecations** under the locked Flutter 3.50.1 SDK in unchanged app/test
  code. No Flutter source or dependency change is included in this task.
- Initial sandboxed Nix/Flutter checks could not write existing caches/access the
  Nix daemon; subsequent checks used the existing locked shells with the required
  local access. No global configuration change was made.

The new transactional ACL block initially exposed a PL/pgSQL variable/query-alias
collision in the synthetic SQL test; it was corrected and the full backend suite
passed afterward. No managed rehearsal, fixture reset, remote database mutation,
existing environment startup/deletion or Phase 2.2 work was used for validation.
