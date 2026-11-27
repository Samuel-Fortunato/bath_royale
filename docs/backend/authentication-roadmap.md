# Authentication roadmap — Private alpha

Current behavior: [A3 community alpha](community-alpha.md) supersedes the earlier optional enable/pause modes and adds anonymous catalogue browsing. Account storage requires clear initial acceptance and then synchronizes automatically. Public publication remains a separate explicit action; archived guests/examples stay excluded. The A1/A2 evidence below is historical.


Current application integration: [A2 private account synchronization](private-account-synchronization.md). A1.1 UX is owner-accepted; A2 enables explicit-consent private synchronization and recovery without guest association/public identity. Test-only/disabled statements below describe the historical foundation milestone, not the current configured app.


## A1 decisions

The priority is a usable private alpha for a small group of friends. Email/password, the official Auth SDK, secure credential vault/restoration guard, account/environment-scoped SQLite, Provider and Material 3 remain unchanged. Authentication remains separate from upload/publication authorization.

A1 removes guest mode as a writable identity. The configured bootstrap initially shows a dedicated authentication screen and opens only a matching account store after authentication. The device scope rejects guest selection. Logout hides the retained account tree and returns to authentication; relogin restores that account's data. Open drafts/failed commits remain protected, including reauthentication to the original account. Offline restoration of a previously authenticated local identity remains allowed after JWT expiry; remote authorization still requires a valid session.

The original guest database is left untouched and is not opened by the A1 bootstrap. Its bathrooms, visits, reviews, favourites, fictional examples and theme remain in the original file. They are not deleted, uploaded or automatically mapped to an account. They are archived rather than visible as a second personal profile. Account files keep the existing schema and namespace; a fresh account starts empty. Account theme settings remain account-specific. No migrations or resets are introduced.

Profile contains a navigation tile to the dedicated account screen, not an embedded login form. Sign-in and registration have separate forms, password visibility, disabled controls/progress during requests, local validation and Portuguese errors above the fields. Incorrect credentials produce visible live-region feedback. Private account email appears only in account management and is never copied into public/domain metadata. Existing humorous ratings and palettes are preserved.

## Local alpha versus production

`backend/auth-compose.yml` is loaded only by `POC_INSTANCE=auth`. It defaults `GOTRUE_MAILER_AUTOCONFIRM` to true for that isolated fictional environment; existing users/volumes are retained. [Supabase Auth configuration](https://github.com/supabase/auth/blob/master/README.md) documents autoconfirm as the server-side control. Other PoC installations and the managed Supabase project are untouched. This file is not a production deployment template.

The separate USB/TLS target uses `AuthConfiguration.localAlpha`, restricted to the exact `https://localhost:55474` endpoint and local placeholder client key. Its policy changes UI guidance/capabilities only: the server still decides whether signup returns a session. Local recovery is intentionally unavailable in the app and is disclosed before requesting any email. Existing password change remains available while signed in. Keep fictional passwords used nowhere else.

The ordinary `AuthConfiguration` still requires production HTTPS and public client keys, defaults to confirmation/recovery-capable UI and accepts the server's confirmation-required response without logging in. There is no ordinary dart-define that disables confirmation or changes platform certificate trust. The confirmation/recovery implementation is retained and tested against the same isolated server temporarily started with `BATH_LOCAL_AUTH_AUTOCONFIRM=false`. Restore the default after that test. Production still needs an approved email-delivery and recovery configuration.

Public preview CI continues building only `lib/main.dart`, without Auth configuration or the local certificate. Its screen explains that the private test build is needed; it has no writable guest fallback. Never publish the configured private APK. Server registration restrictions are an outstanding prerequisite for remote friend distribution: hiding an APK or a registration button is insufficient. No allowlist/invite architecture is selected or implemented here.

## Deferred work and feedback

A2 and historical Phase 2.3C are unstarted. No shared catalogue, synchronization, guest association, public profile, production deployment or managed-project change is included. Unauthenticated catalogue browsing is required once the shared catalogue exists; A1 honestly explains its absence.

Outstanding UI/UX feedback to address in separately scoped work:

- Explore's + action is confusing: clarify creation versus discovery and the action's discoverability.
- Empty states confuse a fresh account or absent catalogue with filters, no personal visits/favourites and offline availability. Distinguish these causes and provide relevant next actions.
- Fictional prototype content needs clearer labels/presentation and separation from genuine shared content. Do not seed or upload archived examples into accounts to fill blank screens.

Before admitting real users or production data, reconsider experimental database reset policy and implement/test non-destructive migrations. Private alpha still needs server registration restrictions, reachable hosting, privacy/deletion and recovery decisions. These are release gates, not hidden client restrictions.

## Verification

Automated coverage includes the actual configured bootstrap with a byte-for-byte preserved legacy SQLite file; no guest opener call; dedicated Profile navigation; registration policy and UI errors/loading; 320/390 px light/dark layouts with 1.5 text scaling and keyboard insets; persisted bathroom/visit/review/favourite records across A/B switching, logout and restart; SDK offline expiry, reconnection and revocation; existing storage/draft regressions. Real fictional HTTPS tests exercise immediate signup, invalid login, separate accounts, file-backed account persistence, rotated credentials, revocation and restoration denial. A separate confirmation-required run covers confirmation and recovery/password change for future deployment.

Physical Keystore and actual phone UX/data acceptance must be reported separately from automated tests and APK compatibility checks. See [the current device procedure](../android-auth-device-testing.md).

Executed checks: **196 ordinary Flutter tests pass** (three opt-in suite placeholders skipped); formatting, strict analysis, locked dependency resolution, **25 offline backend tests**, Ruff lint/format, seven preview-tooling tests and actionlint pass. The new dedicated Material screen is explicitly added to the existing exact import diagnostic baseline; no general suppression. Real HTTPS immediate-signup/account-isolation tests and both TLS tests pass separately; the confirmation-required variant also passes. Private Android/Linux releases and the ordinary unconfigured Android release build pass. The private APK contains the local endpoint/client/certificate in all three native AOT payloads; the public-target APK contains none of them. See the device runbook for the private checksum and installation status.

Initial local attempts exposed a form const-expression error, test scrolling before layout settled and a backend test import-path error; all were corrected before the final passing checks. Flutter cache access required the normal approved toolchain access. ADB device discovery succeeds but reports no connected phone, so installation and physical acceptance remain pending. No application data was cleared.
