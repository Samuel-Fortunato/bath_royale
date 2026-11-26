# Production authentication and device lifecycle — Phase 2.3B

Email/password authentication is optional. With no backend configuration the original guest bootstrap opens the original database without contacting a server or secure storage. Profile exposes account controls when configured. Authentication does **not** back up domain data, associate guest records, authorize synchronization, create an outbox, open public cache snapshots or create a public profile. No synchronization coordinator is constructed.

## Configuration and security

Build/run with public client configuration only:

```sh
flutter run -d linux --dart-define=SUPABASE_URL=https://project.example --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_example
```

Use the Supabase gateway base URL (not the Auth API path). The endpoint identifies the backend environment; subject UUID identifies the account, never email. Keep environment URLs stable across builds. Production requires HTTPS, with no URL credentials/query/fragment. The constructor's explicit loopback HTTP exception is test-only and rejected in release mode. No shipped application flag enables HTTP. Never supply a service-role or secret key; recognized privileged key formats are rejected.

The official Supabase Dart Auth SDK (`supabase` export of GoTrue) owns registration/password verification/token exchange and refresh rotation. We deliberately do not use `supabase_flutter`'s default session persistence. `ProductionAuth` persists the serialized SDK session only through `CredentialVault`, implemented with `flutter_secure_storage` 11.2.0. No passwords are persisted; no tokens enter SQLite, logs or source control. SDK request logging is not enabled. The app does not construct a database/realtime/storage API client.

Android uses the package's default RSA-OAEP/AES-GCM Keystore-backed storage, with automatic reset on storage errors disabled. Android application backup is disabled to avoid exporting credentials or restoring unusable wrapped keys; local data stays on-device. Existing package and preview signing remain unchanged. Linux uses Secret Service through libsecret; the locked project flake now supplies the build/runtime library. A working session D-Bus and unlocked Secret Service provider (such as GNOME Keyring or compatible KWallet) are system prerequisites. Configure these through your desktop, not repository changes to global NixOS/Home Manager. The app reports unavailable/locked storage, offers retry and never creates a plaintext fallback.

Credentials have one environment-specific secure key; it contains only the currently selected SDK session. Account switches require logout first through the UI. Logout removes that environment's credentials before returning to guest; other account SQLite files and committed pending work remain. A storage deletion failure is reported as a failed logout, not success. Best-effort server logout is bounded to five seconds after local deletion. Confirmed remote revocation hides the account immediately even if credential deletion fails; resolve the secure-store failure before reuse. Remote access JWTs may remain server-valid until expiry after logout; local removal cannot retract an in-flight server request.

## Offline behavior and lifecycle

Startup restores the SDK session from secure storage without a network request, including an expired session. This restores a previously authenticated **local identity**, not server authorization. Account files start empty; guest samples/legacy records are never imported. Existing isolated guest/account/environment SQLite names, schema v6 and pending operation IDs are unchanged.

The device scope permits offline local actions for that restored identity even after JWT expiry. `AuthSession.status` still reports expiry, so existing remote guards cannot authorize requests. A periodic foreground-process check attempts renewal near expiry; renewal uses the SDK and persists rotated credentials before publishing the new identity. Concurrent renewals coalesce and auth/storage operations serialize. Generation changes invalidate asynchronous store/synchronization work; superseded or disposed authentication operations cannot publish an identity. Temporary network/server failures retain offline local access. Confirmed refresh-session revocation removes access and credentials. Missing credentials restore guest; locked storage exposes no account and allows guest use plus explicit retry.

The entire Navigator/Provider subtree is replaced on a successful scope change. An inaccessible account tree is hidden and focus excluded while retained in memory. Open editors or failed pre-commit actions block replacement: finish/cancel the editor or retry the failed write first. A revoked session with retained work requires reauthentication to the original account to recover its editor; another account never sees that work. Logout returns to the original guest file and leaves account files intact. Logging back in opens the original account file. Unsaved drafts and failed pre-commit callbacks still cannot survive process death; committed pending work remains durable. SQLite file isolation is not encryption of domain records.

## Confirmation, recovery and delivery gate

Profile supports registration, login, logout, password recovery, email code/verification-link entry and password change. Copy a code or the original verification link from the email into the app; verification links must match the configured backend origin and Auth verification path. No email address becomes public profile metadata. Code-based verification deliberately uses SDK implicit flow without a browser redirect or PKCE verifier; credentials are obtained through the SDK verification call, not URL fragments. Desktop/Android deep-link activation is not implemented.

Supabase Auth supports confirmation and recovery independently of whether a deployment can deliver email. Current official documentation:

- [Default SMTP restrictions](https://supabase.com/docs/guides/auth/auth-smtp): built-in delivery is limited to project team addresses; public delivery needs custom SMTP or another explicitly configured delivery mechanism.
- [Rate limits](https://supabase.com/docs/guides/auth/rate-limits): the built-in provider is limited to two emails per hour.
- [Local email testing](https://supabase.com/docs/guides/auth/testing-auth-flows): local mail capture can verify flows without external delivery.

Public registration/recovery deployment remains gated on an approved zero-recurring-cost delivery arrangement and usable email templates. Confirmation is not silently disabled. No email service, domain or paid resource was selected.

## Isolated verification

```sh
POC_INSTANCE=auth nix develop .#backend --command python3 backend/poc.py start
BATH_REAL_AUTH=1 flutter test test/real_auth_test.dart
POC_INSTANCE=auth nix develop .#backend --command python3 backend/poc.py stop
```

This creates only `bath-royale-poc-auth`, independent private runtime credentials, volumes/network, Auth 127.0.0.1:55471, REST :55472 and Mailpit :55473. The digest-pinned mail container is enabled only for that instance; confirmation stays enabled. Captured messages and fictional tokens are private local test artifacts. Existing managed/migration/sync installations are not accessed.

The opt-in real test exercises SDK registration, required confirmation, login, restart restoration, token rotation, captured recovery, password change and logout. Direct Auth exposes `/verify` rather than the gateway's `/auth/v1/verify`; the test maps captured links to the gateway-form verification path for adapter origin validation while injecting the direct local SDK endpoint. It exercises the adapter's confirmation, recovery verification, password-change and persistence methods. Ordinary tests include SDK HTTP responses for invalid credentials, expiry, offline restoration/local use, coalesced refresh/reconnection, confirmed revocation, locked storage and no domain requests, plus retained account/draft/pending-work regressions.

## Remaining acceptance

- Android physical device: secure-store restart, offline expiry/reconnection, logout and same-account restoration, account/environment isolation, and secure-store failure behavior.
- Linux desktop: actual desktop keyring locking/unlocking and restart across application processes.
- Phone: release-mode confirmation/recovery UX, password visibility, keyboard/text scaling, and retained editor/failed-write recovery.
- Install the signed optimized preview as an in-place update; verify existing guest records/settings remain. No phone data preservation is claimed without this check.
- Production HTTPS/client configuration, confirmed email templates/delivery and service availability.
- Private synchronization consent, explicit guest association, Unicode compatibility, protocol metadata portability and public identity/publication remain open. Phase 2.3C and 2.4 are not started.


Executed verification on 2026-11-26: 178 ordinary Flutter tests pass (170 retained plus eight new; two opt-in real-suite placeholders skipped), unchanged exact strict analyzer baseline, 25 offline backend regressions, Ruff lint/format, actionlint and five preview publication/verification tests pass. The opt-in real Auth test passes separately, including captured confirmation/recovery and stable UUID after password change. A direct SQL count confirms zero public profiles. The new backend is stopped with its independent data retained. An actual Linux plugin write/read/delete probe passed using an isolated session D-Bus and temporary unlocked GNOME Keyring, without touching the owner's keyring. The probe source is `tool/credential_probe.dart`; compile with `flutter build linux --debug -t tool/credential_probe.dart` and run only with an isolated test keyring/session, then rebuild the normal `lib/main.dart` target. No Android device is attached; no emulator or physical Keystore execution is claimed. Full desktop lock/unlock and cross-process device acceptance remain open.

Final builds: Linux debug and authentication-configured release, Android debug and authentication-configured universal release all passed. Configured release compilation used a fictional HTTPS endpoint/publishable key, with no network contact to a production backend. The local release APK verifier confirmed package `com.example.bath_royale`, version `0.1.0` / code `1` (local build only), expected preview certificate, three native architectures, AOT payload and no debug flag/kernel. Do not install local code 1 over newer CI previews; CI retains the existing increasing version scheme. The optimized preview workflow itself is unchanged.
