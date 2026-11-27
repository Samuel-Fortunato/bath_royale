# A3.1 — Community experience simplification

Owner-authorized on 2026-11-27, following accepted A3 functional tests. This supersedes A3 private/shared association, public usernames and manual publication. Flutter, Dart, Provider, Material 3, SQLite and the existing Postgres/Auth/PostgREST stack remain. No managed deployment, configured APK publication, paid services or A4/A5 work.

## Verified milestones and resumption

- **Backend complete:** additive migration `202611270009_community_simplification.sql`, entitlement, anonymous review projection, versioned automatic submission, private compatibility and moderation. Direct API and real two-account Flutter checks pass, including populated logical export/restoration.
- **Application complete:** shared-only normal workflows, review-first Explore action, anonymous navigation, Settings/account/recovery, concise storage acceptance and linked provisional privacy information. SQLite v9 migration preserves original rows, references, outbox and acceptance. Ordinary regressions and strict analysis pass.
- **Fixtures complete:** isolated rootless `fixtures` backend, idempotent fictional dataset, private credentials reference and separately compiled one-tap account selector. Real SDK login/projection checks pass for all five accounts. Distributable APK scans and dependency guards exclude the selector and credential payload.
- **Delivery:** private alpha and development Android releases, unconfigured distributable Android release and configured Linux release built successfully. The owner explicitly authorized replacing the alpha on the connected phone with development; the in-place update succeeds with original signing identity and data retained. Final artifact evidence is below. Owner physical acceptance remains separate.
- **Documentation/backlog:** current model, commands, checks, device procedure and A4 feedback consolidated. Commit/push identifiers and current hosted CI status are supplied in the delivery report.

Resume by inspecting Git status, this file and ROADMAP.md. Never reset `auth` or `fixtures`, reseed an owner account, publish configured artifacts or treat installation as owner acceptance.

## Product and privacy boundaries

One shared catalogue contains official (`origin=curated`) and community bathrooms. Stable server identities and normalized-name duplicate prevention remain. New bathroom creation requires `app_private.bathroom_creators` membership. Only protected administrators can grant/revoke it through `grant_bathroom_creation(account_email, allowed)`; editable Auth metadata conveys no privilege. Administrators also need the entitlement to contribute; the fictional administrator has it. This is a persistent permission representing a future power-up, with no acquisition, achievements or consumption rules.

New reviews use `createCommunityReview` or atomic `createCommunityVisitReview`. The UI discloses that scores, tags and optional comments will be public and anonymous before saving, including when queued offline. The server validates an available shared bathroom and atomically creates/publishes the owned review using existing durable operation receipts and revision/conflict rules. Duplicate/lost acknowledgements replay the same outcome. Normal users neither choose publication nor supply a public username.

Public reviews contain only an independent random **per-review** ID, shared bathroom ID, scores, tags and comment. There is no stable public author ID, username, private review/visit ID, exact visit date, account ID, email or favourite. Community details/rankings consume these published projections only. The server retains private ownership for editing/deletion, abuse reports and hide/restore moderation. Deleting a review removes its public projection while retaining its visit; deleting a visit confirms removal of its review too. Offline edits/deletions take effect remotely on delivery, and disconnected public caches update on reconnection.

Historical private commands remain compatible solely to preserve durable pending/backfill work and old account records. They remain private, even when referencing a shared bathroom. New manual `publishReview`, `setUsername` and `linkBathroom` commands are denied; exact receipts for already completed commands remain replayable. No migration republishes private history. Previously published A3 reviews remain published with anonymous attribution. Original private bathrooms, links, visits, reviews and favourites remain stored; Settings → **Registos anteriores** offers read-only recovery/copying of old comments, without automatic reassociation, deletion or publication.

Account storage synchronizes automatically after persistent acceptance. Existing acceptance survives upgrades; accounts lacking it see a concise explanation and privacy link before upload/actions. Guest archives and demo/unclassified examples never pass the upload gate. The provisional privacy text describes behavior and unresolved policies; it does not establish legal compliance.

## Application and storage

Normal Explore, details, collection and rankings compose shared identities with the current account's personal records. Public pulls never overwrite private domain rows. Personal references survive hidden/unavailable catalogue entries. SQLite v9 adds `catalogue_classifications`; only obsolete public attribution cache/checkpoints are invalidated. Equal-revision refresh is allowed for public projection fields, while private conflict/revision protection stays strict.

Signed-out navigation is **Explorar / Rankings / Conta**. Personal collection, profile statistics, favourite controls, discovery labels and details' visits tab are hidden. No writable guest identity is opened. Explore's primary action starts a review of an existing bathroom; entitled users receive a separate creation action. Successful changes and foreground events refresh automatically, with pull-to-refresh and no idle polling. Durable offline operations, conflict preservation and safe recovery remain.

The private email identifies the signed-in account. Settings groups account/password/logout, detailed storage diagnostics and recovery. Ordinary users see no moderation/entitlement controls. UI redesign remains in [the A4 backlog](../bath-royale-design/ui-design.md#a31-functional-simplification-and-a4-backlog).

## Isolated development fixtures

`POC_INSTANCE=fixtures` uses independent rootless volumes, secrets and loopback ports **55501/55502**. It is separate from the retained owner `auth` installation on **55471/55472**. `backend/seed_development.py` refuses all other instances before network/IO, has no managed-URL option, verifies local bindings and refuses unowned existing account collisions without resetting passwords or authenticating those accounts. Deterministic object/operation IDs and preserved receipts make reseeding idempotent; existing fixture edits/deletions are not overwritten. No fixture schema/data is part of production migrations.

| Fictional account | Role/activity |
| --- | --- |
| rei@example.com | Administrator and creation entitlement; 3 visits / 3 reviews |
| duque@example.com | Creation entitlement; 4 visits / 3 reviews |
| cavaleiro@example.com | Frequent reviewer; 12 visits / 9 reviews |
| escudeiro@example.com | Occasional reviewer; 2 visits / 2 reviews |
| novato@example.com | Empty personal account |

The dataset has **8 bathrooms (4 official / 4 community), 21 visits, 17 anonymous public reviews and 11 favourites**. Two bathrooms have no activity. Comments are fictional PT-PT, ratings/tags vary, and repeated/unreviewed visits exercise history. Every bathroom is visibly marked **Exemplo fictício**. The requested shared password is kept only in the private local files, never source or CI.

On this workstation, the owner-only directory is `/home/samuel/.local/state/bath-royale-a31-development`:

- `test-accounts.txt`: simple email/password reference requested by the owner.
- `password.txt`: owner-only seed input; do not commit or print in logs.
- `defines.json`, `development-defines.json`, `server.pem`, `server.key`: local TLS/configuration; private key and credential payload stay outside Git.
- Saved private APKs, installation evidence and gateway PID/log.

Reproduce from the project root with the existing Nix environment. Prepare a private directory and password file outside Git for another workstation; supply the requested development password interactively, not in repository scripts or shell arguments. The gateway `prepare` creates only local TLS configuration; seeding generates the private development defines and reference file.

```sh
python3 tool/development_device_proxy.py prepare /private/path/to/development
POC_INSTANCE=fixtures nix develop .#backend --offline --no-write-lock-file --command python3 backend/seed_development.py --password-file /private/path/to/development/password.txt --output-dir /private/path/to/development --device-config /private/path/to/development/defines.json --verify-idempotency
python3 tool/development_device_proxy.py serve /private/path/to/development
```

On this workstation, use the existing persistent directory and default XDG state; do not run `prepare` again while its gateway uses the existing certificate. Backend secrets are retained in `~/.local/state/bath-royale-poc-fixtures`. Stop/start preserves volumes and fixtures. Never use `clean` for retained instances.

Only **`tool/local_development.dart`** reads `BATH_LOCAL_TEST_ACCOUNTS`, guarded by `BATH_ISOLATED_DEVELOPMENT` and the exact `https://localhost:55504` / `local-development-client` configuration before decoding. Its TLS gateway forwards solely to the fixture ports over USB. `lib/main.dart` and `tool/auth_device_preview.dart` cannot reach the selector implementation or fixture credentials. The installer rejects development defines in alpha builds and managed endpoints in both local targets. Actual unconfigured/alpha release payload scans verify absence; the development scan verifies presence. Do not distribute even the local development APK.

## Reproduce verification

The following runners use disposable `community` / `protocol` installations, independently retained outside Git. Never substitute the owner's `auth` or the fixture instance. They stop their own containers afterwards. Assertion counts can grow with retained feed pagination.

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_analysis.dart
flutter test
nix develop .#backend --offline --no-write-lock-file --command env PYTHONPATH=backend python3 -m unittest discover -s backend/tests -p 'test_*.py'
python3 -m unittest discover -s tool -p 'test_*.py'
POC_INSTANCE=community XDG_STATE_HOME=/tmp/bath-a3-state nix develop .#backend --offline --no-write-lock-file --command python3 backend/community.py --flutter
POC_INSTANCE=protocol XDG_STATE_HOME=/tmp/bath-a3-state nix develop .#backend --offline --no-write-lock-file --command python3 backend/synchronization.py
BATH_DEVELOPMENT_CONFIG=/private/path/to/development/development-defines.json flutter test test/real_development_test.dart
python3 tool/verify_development_isolation.py /private/path/to/alpha.apk --config /private/path/to/development/development-defines.json
python3 tool/verify_development_isolation.py /private/path/to/development.apk --config /private/path/to/development/development-defines.json --development
```

Executed locally on 2026-11-27:

- **221 ordinary Flutter tests pass**, five opt-in placeholders skipped; strict analyzer baseline, Dart formatting and whitespace pass.
- **30 offline backend tests and 13 tooling tests pass**; backend Ruff checks and workflow actionlint pass. An initial backend unit invocation from the wrong working directory failed module imports; rerunning with the documented module path succeeds.
- A3.1 community runner: **62 direct API/privacy/entitlement assertions including actual two-account Flutter integration**, followed by populated logical export/restore. Covers no profile requirement, anonymous submission/edit/deletion, old private history, entitlement grant/revoke/direct bypass, metadata spoofing, account/feed isolation, duplicate prevention, reporting/moderation and current-visibility historical replay.
- Complete current protocol runner: **60 A3.1 authorization assertions, 1,093 Unicode vectors, 344 server assertions, profile-free ownership/API/feed isolation and 8 real Flutter sync tests**, followed by metadata/receipt/cursor/sequence/clock restoration. It exercises lost acknowledgement, offline queue/restart, compound writes, conflicts, session/expiry guards and demo exclusions. Long real token-expiry waits were not repeated; existing Auth behavior remains covered by prior milestones and current SDK tests.
- **3 actual HTTPS Auth/device tests** and **1 actual five-account development SDK/catalogue/private-projection test** pass. The latter verifies all personal counts and privileges separately against the same public catalogue.
- Repeated seeding preserves all domain row hashes/counts and account IDs/email/password hashes. Existing unowned account preservation, wrong-instance refusal and credential path guards have unit regressions.
- Private alpha, local development and unconfigured universal Android release builds pass, with expected AOT/signature/package checks and actual development-fixture presence/absence scans. Configured Linux release passes. No configured APK is published.

## Android delivery and physical acceptance

The connected SM A166B received private alpha `0.1.0-alpha-a31.1023`, then the owner explicitly approved the development replacement. The final development installation is `0.1.0-dev-a31.1023`, code **1023**, package `com.example.bath_royale`, original certificate SHA-256 `4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc`, app ID **10419**, and unchanged first-install time **2026-11-26 22:40:55**. All updates use `adb install -r`, without uninstall/downgrade/clear. Original owner account stores and secure sessions remain separate under their original backend namespace. No acceptance or review was submitted on the owner's behalf.

The local development gateway is `55504` (USB reverse), alpha remains `55474`. Phone launch, anonymous fictional catalogue/navigation/details and the five-account selector were visually inspected; human acceptance of interactions, offline restart and secure restoration remains pending. Saved artifacts and current hashes are recorded in the private `alpha-verification.json` / `development-verification.json` alongside the APKs. See [device procedure and concise acceptance](../android-auth-device-testing.md#a31-development-build-and-acceptance).

Final saved alpha SHA-256: `f21e64c60d133efcd2159a6d0eceffa1c3176bead6fb4bec36478d78e3f0c99e`. Final installed development SHA-256: `6ebfdbfb8f8900470f76d1feb7c1b2be453529986ac444fc724ee2d9e25a47ce`. Each private APK is 59,640,954 bytes. The final unconfigured APK is 50,646,130 bytes and contains no fixture payload. The saved final alpha includes the same final notice/card corrections; the development variant is the one installed by owner choice.

Remaining decisions: future entitlement acquisition/consumption and revocation UX, remote registration restrictions, production privacy/retention/erasure/legal review and hosting/email release gates. Comprehensive visual work belongs to A4; achievements/power-ups beyond this protected entitlement belong to later approved scope.
