# A3 community alpha

Owner-authorized scope, 2026-11-27: automatic accepted account storage, anonymous shared catalogue, explicit authenticated contributions/publication, public usernames, reporting and administrative moderation. Flutter, Provider, Material 3, SQLite and the existing Postgres/Auth/PostgREST protocol remain. No managed deployment, private APK publication, paid services, A4 or A5.

## Independently verifiable milestones

- **Backend complete:** additive `202611270008_community.sql`; direct API authorization, cross-account isolation, publication/edit/withdrawal, duplicate contributions/reports, current-visibility historical replay and moderation. The standalone runner passes **85 assertions** and populated community/private export/restoration. With `--flutter`, it also runs the actual two-account client integration (86 assertions including that suite result).
- **Account storage and application implemented:** onboarding acceptance, anonymous durable cache, composed catalogue/personal state, contributions, links, usernames, publication/withdrawal and moderation controls. **223 ordinary Flutter tests pass**, with four opt-in placeholders skipped. Includes v7 → v8 preservation, retained guest bytes, durable offline cache/queues, aggregate isolation, duplicate recovery and 320 px/large-text coverage. Final release checks/delivery remain below.
- **Protocol regression complete:** the isolated `protocol` runner passes **231 authorization/authentication assertions**, **1,093 Unicode vectors**, **237 server protocol assertions**, profile-free privacy checks and **8 real Flutter synchronization tests**, followed by logical export/restoration, receipts, cursors, sequence and clock checks. The final run skips repeated real JWT-expiry waits; those already passed in the earlier full run with unchanged Auth configuration.
- **Delivery pending:** final formatting/strict analysis, final releases, retained local phone-backend migration, update-only APK installation, documentation and Git delivery. Phone UX/Keystore/two-human-account acceptance remains owner work, distinct from installation.

Inspect Git status and this document before resuming. Do not infer transfer/publication authorization from Auth identity, a username or a private association. A milestone is complete only with recorded executed checks.

## Storage and synchronization

Account storage is automatic after a persistent acceptance on each account/device. Existing A2 consent is retained. An absent/previously paused preference shows the explanation before transfers or account actions; it includes existing private account records. The user may accept offline or log out and browse the catalogue anonymously. There are no normal enable/pause modes. Foreground retries, durable operations, discreet status, explicit retry and conflict/correction/archive/replay recovery remain. The original guest file is never opened or associated; demo/unclassified data never passes the upload gate.

SQLite **v8** adds `catalogue_bathrooms` and `bathroom_links`; it preserves domain rows, consent, outbox, metadata and settings. The public cache uses the existing environment-scoped public database and catalogue feed. It never stores private visits, reviews, favourites, email or account operations. Personal account stores retain shared bathroom parents for their own history even when public content becomes unavailable. Cached names are not permission to publish unavailable content.

Shared entries compose public identities/reviews with private visits, ratings and favourites. Association maps the original private bathroom ID to a shared ID without rewriting the bathroom, visit, review or favourite identifiers. Linking does not publish history. The association is deliberately immutable in this alpha; correction/relinking needs a subsequent product decision. A rejected queued link can be archived safely. Duplicate pending contributions cannot collect visits before server acceptance; they can be corrected or archived without losing original input.

## Backend boundaries

New contributions create `community=true`, unverified public catalogue rows. A normalized-name unique index plus a transaction-locked check against existing approved rows prevents basic duplicates. There is no fuzzy/geographic matching or external service. Existing account-private rows stay private and cannot be promoted by the old approval path. A contribution is explicitly labelled public before submission.

Public `public_catalogue()`, `public_reviews()` and `sync_pull('catalogue')` return allowlisted fields. Base bathroom/profile rows containing Auth IDs are author/moderator scoped. Public reviews use independent random review/author IDs and a user-chosen username, never private review/visit IDs, exact dates, favourites or email. Ratings/rankings consume these published projections only; own unpublished reviews never become community scores.

A public username is optional for private account use and contribution, mandatory for review publication. It is unique, lower-case, 3–30 ASCII letters/digits/underscore, beginning with a letter. Changing it updates attribution. Publishing is an explicit owner command after private review synchronization; future edits to that published review are public until withdrawal, disclosed by the publication dialog. Withdrawal preserves the private visit and review. Deleting an owned review/visit removes its public projection. Offline publication/withdrawal takes effect remotely after delivery; already disconnected devices may retain their cache until refreshed.

Community commands extend the existing account-scoped receipt/CAS/dependency protocol. They retain operation IDs on retry, reject replay with altered payload, preserve conflicts and never accept an owner supplied by the client. Generic REST writes cannot change `published`, moderation state, shared flags or contributor identity. No new queue service, Realtime subscription or always-on polling is introduced.

Authenticated reports enter a protected private table; repeated reporter/content submissions produce one report. Moderator membership comes only from `app_private.moderators`, never editable Auth metadata. The protected moderation RPCs list minimal reports and hide/restore reviews or bathrooms; they do not expose visits or reporter emails. The app includes a small team-only moderation screen. No manual approval is required for each review/contribution. Historical public feed replay resolves **current** visibility/content, so withdrawn/hidden text cannot be recovered by choosing an older cursor. The migration rebuilds the public review cache projection and expires public cursors; private/domain data is preserved.

## Reproduce isolated verification

Use the existing locked Nix environment. These named instances have independent credentials/volumes and rootless loopback-only listeners; `community` uses 55481/55482 and `protocol` 55491/55492. Their state remains outside the repository. The runners stop their containers afterwards.

```sh
POC_INSTANCE=community XDG_STATE_HOME=/tmp/bath-a3-state nix develop .#backend --offline --no-write-lock-file --command python3 backend/community.py
POC_INSTANCE=community XDG_STATE_HOME=/tmp/bath-a3-state nix develop .#backend --offline --no-write-lock-file --command python3 backend/community.py --flutter
POC_INSTANCE=protocol XDG_STATE_HOME=/tmp/bath-a3-state nix develop .#backend --offline --no-write-lock-file --command python3 backend/synchronization.py
nix develop .#backend --offline --no-write-lock-file --command env PYTHONPATH=backend python3 -m unittest discover -s backend/tests -p 'test_*.py'
```

For a fresh migration rehearsal, use `backend/poc.py clean` **only** with the disposable instance being rehearsed. Never clean the phone's retained `auth` instance or a managed project. The first community run seeds private A2 rows before applying A3 and compares them afterwards. Repeated runs retain isolated fictional fixtures. Assertion counts involving feed pagination can grow with retained test history.

Moderator provisioning is an explicit administrative SQL insert of a test user's UUID into `app_private.moderators` in the isolated database. No credential/privileged role goes in Flutter. Production registration restrictions, hosting, email delivery, retention/erasure and real-user migrations remain release gates. No claim of production readiness or physical acceptance follows from these tests.
