# Private Android account preview

Current procedure and acceptance: [A3.1 development build](#a31-development-build-and-acceptance). Earlier A2/A3 sections retain historical evidence; their pause, manual association, username and publication instructions are superseded.

The ordinary GitHub APK is intentionally **without Auth configuration** and A1 shows an account-service-unavailable screen: its `lib/main.dart` build has no `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`. Do not add a development endpoint, CA, signing material or Auth credentials to that workflow or publish the APK described here. Backend deployment and public email delivery remain separate approval gates. This procedure uses only the independent `bath-royale-poc-auth` installation, fictional accounts, local mail capture and USB. It never needs the existing managed project, a paid service, a domain or a public listener.

## HTTPS without a public deployment

`tool/auth_device_preview.dart` is a separate, explicitly selected entry point. It accepts only `https://localhost:55474` and the placeholder `local-device-client`. The direct isolated Auth server does not require a gateway API key; this placeholder conveys no elevated privilege and must never be substituted for a managed project's secret/service-role key.

The target uses a fresh Dart `SecurityContext` containing only the supplied short-lived localhost certificate. Certificate trust, hostname and expiry validation stay enabled; there is no `badCertificateCallback`, HTTP exception or OS-wide CA installation. See Dart's [custom trusted certificate support](https://api.dart.dev/dart-io/HttpClient-class.html) and [SecurityContext](https://api.dart.dev/dart-io/SecurityContext-class.html). The public certificate alone enters the APK. Its private key stays on the development computer outside the checkout. The ordinary app entry point never imports this target or changes its platform TLS trust.

`tool/auth_device_proxy.py` terminates TLS exclusively on computer loopback port 55474 and proxies `/auth/v1/` to the independent Auth listener on 127.0.0.1:55471. It additionally forwards only `/rest/v1/rpc/sync_submit` and `/rest/v1/rpc/sync_pull` to 127.0.0.1:55472 for A2. Other REST paths and public RPCs return 404. It prints no requests or tokens. `adb reverse` carries the phone's localhost connection over USB. Unplugging USB or removing that forwarding disconnects Auth. This is a local transport test, not evidence of production HTTPS or email delivery.

## Prepare the computer and phone

Use the locked Nix/direnv development environment and keep normal sandboxing. Commands below assume tools are already on PATH; use `direnv exec . <command>` if needed. OpenSSL, when absent, is provided temporarily from the committed flake input. No global NixOS/Home Manager change is needed.

1. Connect the phone by USB, enable USB debugging and accept the computer's authorization prompt. `adb devices -l` must report `device`, not `unauthorized`. If multiple devices are attached, set `ANDROID_SERIAL` to the chosen serial for every command.
2. Preserve the existing installation and its data. Android updates require the same package/certificate and a version code at least as large as the installed one. See [Android signing](https://developer.android.com/studio/publish/app-signing) and [versioning](https://developer.android.com/studio/publish/versioning).
3. Point `PREVIEW_KEYSTORE` at the original development key or its secure backup. A GitHub secret cannot be downloaded to recover a lost private key. Never generate a replacement to work around a certificate mismatch.

```sh
adb devices -l
export PREVIEW_KEYSTORE=/path/to/original/debug.keystore
python3 tool/verify_preview.py key "$PREVIEW_KEYSTORE"
device_dir=$(mktemp -d /tmp/bath-auth-device.XXXXXXXX)
installed_apk=$(adb shell pm path com.example.bath_royale | python3 -c 'import sys; print(next(s.strip().removeprefix("package:") for s in sys.stdin if s.startswith("package:") and s.strip().endswith("/base.apk")))')
adb pull "$installed_apk" "$device_dir/installed.apk"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs "$device_dir/installed.apk"
device_code=$(adb shell dumpsys package com.example.bath_royale | python3 -c 'import re,sys; m=re.search(r"versionCode=(\d+)",sys.stdin.read()); assert m, "Installed version missing"; print(m[1])')
```

Check that the installed certificate SHA-256 is exactly:

```text
4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc
```

The key verifier checks the same fingerprint. If either fails, stop and recover the matching key; do not uninstall or clear storage. The build below deliberately **reuses the installed code** with a distinct version name. Equal version codes support in-place updates and allow returning to an ordinary CI preview with an equal or higher code. Choosing an arbitrarily huge code would block future lower-numbered CI previews. Do not use `adb install -d` to bypass version checks. Our build-only verification uses code 1, which is not evidence that code 1 is compatible with the phone's current preview.

## Start the isolated backend and TLS gateway

```sh
POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py start
nix shell --inputs-from . nixpkgs#openssl --command python3 tool/auth_device_proxy.py prepare "$device_dir"
adb reverse tcp:55474 tcp:55474
python3 tool/auth_device_proxy.py serve "$device_dir"
```

Leave the gateway running in that terminal. In another terminal, reuse the same `device_dir`, `device_code` and `PREVIEW_KEYSTORE` values. `prepare` refuses to overwrite existing certificates/configuration or place credentials inside the checkout. Files are private, the certificate lasts seven days, and `defines.json` contains only the local URL, placeholder client key and public certificate. This temporary shell uses the committed flake input and may fetch its locked packages from the Nix cache. Add `--offline` only when they are already cached; do not install the utility globally.

The backend remains rootless, with independent state/credentials/volumes/network and loopback-only bindings. A1 defaults to server-side email autoconfirm only in this isolated `auth` instance. Local-alpha password recovery is unavailable in the app and clearly disclosed. Production confirmation is retained; see [A1 policy](backend/authentication-roadmap.md). Mailpit remains available on the computer at `http://127.0.0.1:55473`; optional USB forwarding below also makes it available on the authorized phone. Do not expose Auth or Mailpit to the LAN. Starting/stopping this instance does not select a managed Supabase project.

## Build, verify and install locally

```sh
flutter pub get --enforce-lockfile
BATH_DEVICE_TLS_DIRECTORY="$device_dir" flutter test --no-pub test/device_preview_test.dart
BATH_REAL_AUTH=1 BATH_DEVICE_TLS_DIRECTORY="$device_dir" flutter test --no-pub test/real_auth_test.dart
flutter build apk --release --no-pub --target tool/auth_device_preview.dart \
  --dart-define-from-file="$device_dir/defines.json" \
  --build-number "$device_code" --build-name "0.1.0-alpha-a2.$device_code"
python3 tool/verify_preview.py apk build/app/outputs/flutter-apk/app-release.apk \
  "$device_code" "0.1.0-alpha-a2.$device_code"
cp build/app/outputs/flutter-apk/app-release.apk "$device_dir/bath-royale-alpha-a1.apk"
adb install -r "$device_dir/bath-royale-alpha-a1.apk"
```

The verifier checks `com.example.bath_royale`, exact version, existing certificate, non-debuggable universal AOT payload and absence of the debug kernel. Never upload this private APK to GitHub Releases or replace the ordinary public preview. Build from a reviewed commit and record its SHA, version, certificate and checksum with your test notes. Installing with `-r` preserves app storage; actual preservation still needs the checks below. If installation fails, stop without uninstalling. To return to the public preview, first finish/cancel editors and log out, then install the unconfigured APK with the same certificate and an equal or higher code. A1 public previews do not expose the archived guest profile.

For Linux compilation of the same device target:

```sh
flutter build linux --release --no-pub --target tool/auth_device_preview.dart \
  --dart-define-from-file="$device_dir/defines.json"
```

Use a working unlocked desktop Secret Service when executing it. This build command alone does not verify the desktop keyring lifecycle.

## Exercise A1 on the phone

Use fictional emails such as `device-alpha-a@example.com` and passwords used nowhere else. Keep the USB Auth forwarding active: `adb reverse tcp:55474 tcp:55474`. No inbox, confirmation code or recovery email is needed for A1. Do not expose listeners to the LAN.

1. Open the app: it shows the dedicated sign-in screen, with a separate **Criar conta** action. Old guest records remain archived in their original file; they are not shown or automatically associated. A fresh account starts empty, with no fictional samples imported.
2. Create account A. Registration opens the account immediately, without confirming email. In Explore, **+** creates a bathroom; register a visit, write a review and favourite it. These records remain local to A on this phone.
3. In **Perfil → A minha conta**, confirm that email is private and log out. Try a wrong password: **Email ou palavra-passe incorretos.** must be visible. Sign in correctly; A's committed data must return.
4. Force-stop/reopen. The selected account must return without password entry. Remove only Auth forwarding with `adb reverse --remove tcp:55474`; wait beyond the local 60-second JWT lifetime, then force-stop/reopen. Local account data and actions must remain usable. Restore forwarding with `adb reverse tcp:55474 tcp:55474`; renewal must resume without repeated visible churn.
5. Log out and create account B. It must start empty, without A's records or guest examples. Add a distinct bathroom, log out and return to A. Verify A still has its original visits, reviews and favourites. Restart after logout must remain on authentication.
6. **Esqueci-me da palavra-passe** must clearly state recovery is unavailable in this local alpha and offer return to sign-in. Check visibility controls, loading states, keyboard, large text and back navigation. Do not use passwords you cannot replace.

Package/certificate/version compatibility and unchanged app ID/first-install time establish in-place update evidence, not a direct inspection of private Android SQLite/Keystore data. Without root/debuggable access we do not claim byte-level preservation of the phone's files. Automated A1 upgrade tests separately preserve an existing guest SQLite file byte-for-byte while using separate account files. The physical app does not expose the archived guest writer.

Retained editor/failed-commit checks remain relevant: finish/cancel before logout; after auth loss, reauthenticate to the original account to recover memory-only work. Another account cannot replace it. Process death cannot preserve unsaved controller drafts. For controlled revocation only, delete the fictional session in the exact isolated container; never clear application storage or Android Keystore:

```sh
podman exec bath-royale-poc-auth-db psql -X -U supabase_admin -d postgres \
  -v ON_ERROR_STOP=1 -c "DELETE FROM auth.sessions WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'device-alpha-a@example.com');"
```

### Verify future confirmation/recovery support separately

Temporarily switch only this isolated test server to confirmation-required mode, run the real suite with ordinary production UI policy, then restore local-alpha defaults before manual testing:

```sh
BATH_LOCAL_AUTH_AUTOCONFIRM=false POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py start
BATH_REAL_AUTH=1 BATH_REAL_AUTH_CONFIRMATION=1 BATH_DEVICE_TLS_DIRECTORY="$device_dir" flutter test --no-pub test/real_auth_test.dart
POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py start
```

This checks captured confirmation, recovery, password change and recovery intent across restart without modifying a managed project. Mailpit/inbox-helper tooling is retained for that purpose, but is not part of the A1 phone flow. Default tests exercise immediate registration.

## Stop and record limits

Stop the gateway with Ctrl-C, then:

```sh
adb reverse --remove tcp:55474
POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py stop
```

Keep the isolated backend data and the original signing-key backup. Remove the private temporary device directory only when its test APK/certificate are no longer needed. Regenerating a certificate requires rebuilding the local target; it does not require clearing phone data.

## Historical prepared Phase 2.3B session — 2026-11-26

This is the earlier confirmation-required build and procedure, superseded by A1 above. It does not record an A1 installation.

The authorized SM A166B was verified with package `com.example.bath_royale`, installed version `0.1.0-preview.23` / code **1023**, and the documented certificate. The existing local preview key was located and checked without printing its contents. The private application was built from the unchanged app sources at `ccce2ea`, with the local HTTPS certificate embedded, version `0.1.0-auth-local.1023` and the same code **1023**. Package, exact version, certificate, universal native architectures, AOT and non-debuggable status were verified before `adb install -r` returned **Success**. Post-update Android app ID and first-install timestamp are unchanged; actual guest/domain data preservation is still for the owner to verify.

Private APK SHA-256:

```text
04ec17451a879e577e3cc45a38c522381f856179e7a1f9ad0ed40cdf87392acb
```

Private session files, original APK, release APK, certificate, process IDs and before/after metadata are in `/tmp/bath-auth-acceptance-0m55gulo` (mode 0700). The signing key remains in its existing location, outside that directory. No credentials/tokens or private APK are committed or published. The first metadata probe expected `userId`; the phone reports `appId`, so the parser was corrected before compatibility verification and installation. An initial ADB execution approval review timed out; the permitted retry succeeded.

The isolated Auth/Mailpit containers, HTTPS gateway and inbox helper are left running for manual acceptance. Only loopback listeners are published; USB forwards ports 55474 (Auth HTTPS), 55475 (copy helper) and 55473 (full Mailpit). If USB reconnect removes forwarding, reapply all three `adb reverse tcp:<port> tcp:<port>` commands. The helper was opened in the phone browser; no owner registration, login, confirmation or recovery was performed automatically.

For an offline test, leave the helper available and remove only Auth forwarding:

```sh
adb reverse --remove tcp:55474
# Wait beyond the local 60-second JWT lifetime, force-stop/reopen and check local data.
# Restore Auth access afterwards:
adb reverse tcp:55474 tcp:55474
```

To stop this prepared session after testing (do not run while manual acceptance is ongoing):

```sh
kill "$(cat /tmp/bath-auth-acceptance-0m55gulo/gateway.pid)" "$(cat /tmp/bath-auth-acceptance-0m55gulo/inbox.pid)"
adb reverse --remove tcp:55474
adb reverse --remove tcp:55475
adb reverse --remove tcp:55473
POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py stop
```

Preparation checks passed: 189 ordinary Flutter regressions, the unchanged strict analyzer baseline and formatting, 25 offline backend tests, Ruff lint/backend format, actionlint, seven preview-tooling tests (including two inbox regressions), the separate two-test TLS target suite, the real Auth lifecycle over HTTPS, and the verified code-1023 Android release build. The inbox was also checked against captured fictional Mailpit messages without consuming links or printing tokens.

Preparation verifies installation compatibility and local tooling, **not physical authentication acceptance**. Owner checks in the matrix above remain pending: existing guest records/settings, actual Android Keystore restart, USB-forwarded Auth, offline/reconnection, logout/relogin, separate accounts, recovery, retained drafts and phone UX. Linux desktop keyring lock/unlock remains open. The managed Supabase project, global NixOS configuration, public preview workflow and Phase 2.3C are untouched.

## A1 verification and private artifact

A1 passes 196 ordinary Flutter tests (three opt-in placeholders skipped), strict analysis accepting only the documented Material import debt, and the separate real HTTPS signup/A-B persistence/revocation suite plus two TLS-target tests. A confirmation-required real run separately passes confirmation/recovery/password change. Local alpha autoconfirm is restored afterwards. All 25 offline backend regressions, Ruff lint/format, seven preview-tooling regressions and actionlint pass. Private Android/Linux release builds and the ordinary unconfigured Android release pass. All three public AOT payloads exclude the private endpoint/client/certificate; all three private payloads contain the intended local configuration. Dependency resolution remains locked.

The signed private release is `0.1.0-alpha-a2.1023` / code **1023**, reusing the last verified installed version code and existing certificate. APK verification confirms the original package/certificate, exact version, universal AOT release and non-debuggable status. Private artifact: `/tmp/bath-alpha-a1.4ccqocs2/bath-royale-alpha-a1.apk`; SHA-256:

```text
4b15d985f0540c09512adc5e4b6af07de10b9080fe42eac3d904526625ed08bb
```

A1 installation is currently pending: ADB reports no connected device. Recheck the current phone version/certificate when it reconnects before using `adb install -r`; rebuild with its actual code if it is above 1023. Never uninstall, clear data, force a downgrade or use a replacement signing key. No A1 physical acceptance is claimed by these build/test results. Local Auth and the existing HTTPS gateway are left available; USB forwarding must be restored when the device reconnects. The certificate expires seven days after its original generation; preparing a new certificate then requires a new private build.

## A1.1 local install command

Inside the existing direnv/Nix shell, connect/authorize the phone and keep the isolated Auth backend and TLS gateway running. Reuse the existing private TLS directory (its certificate must still be valid) and original signing key:

```sh
PREVIEW_KEYSTORE=/home/samuel/.config/.android/debug.keystore python3 tool/install_private_alpha.py --config-dir /tmp/bath-auth-acceptance-0m55gulo
```

Use `--keystore /path/to/original/key` or `PREVIEW_KEYSTORE` for another existing backup, and `ANDROID_SERIAL` if multiple devices are attached. The command refuses a missing installation or incompatible certificate, reads the installed version code, builds the configured private release, verifies its exact package/version/signature/AOT payload, uses only `adb install -r`, restores `tcp:55474` USB forwarding and launches Bath Royale. It never uninstalls, clears storage, selects a managed project or publishes an APK. Private output stays under ignored `build/`. See the preparation instructions above when a new TLS certificate is needed.

A1.1 physical checks: signed-out startup/logout show welcome; Entrar and Criar conta open separate routes with app-bar/system back to welcome. Short registration passwords show a field error and remain editable; short existing-account passwords are sent to sign-in without applying registration minimums. Wrong credentials keep their existing feedback and destination. Check email autofill/password-manager selection, Next focus movement, Done submission, keyboard scrolling and restored authenticated startup. Android password-manager suggestions depend on the enabled provider and saved credentials; widget tests cannot establish device-provider behavior.

A1.1 verification: 197 ordinary Flutter regressions pass (three opt-in placeholders skipped), strict analysis passes with only the existing exact Material-import baseline, Dart formatting passes, and all nine tooling tests pass. The new tests cover short registration-password retention, separate routes with app-bar/system back, email autofill/Next, grouped autofill, short sign-in reaching the server and visible incorrect credentials; existing lifecycle tests cover restored accounts and welcome on logout/startup. The update-only installer also rejects mismatched certificates before building/installing.

The connected SM A166B accepted `0.1.0-alpha-a11.1023` / code 1023 with the existing verified certificate and package via `adb install -r` (Success). The command restored `tcp:55474` forwarding and Android accepted the launch intent. No uninstall/storage-clear operation was used. Actual Android password-manager suggestions and owner UX acceptance remain separate from automated verification.


## A2 physical acceptance

The owner accepted A1.1 authentication UX before A2. The account-management screen retains logout; **Alterar palavra-passe** no longer includes it. The update-only installer now names the private build `0.1.0-alpha-a2.<installed code>`, keeps the existing signing identity and uses `adb install -r`. Never clear storage, uninstall or publish this configured artifact.

1. Reopen the updated app and verify the existing account, bathrooms, visits, reviews and favourites. Profile → **Sincronização privada** initially says **Só neste dispositivo**. Open it, read the explanation and choose **Agora não**; nothing uploads. Activate explicitly when ready. Only records owned by this account are included, never archived guest data or examples.
2. On another independently stored installation using the same isolated backend, sign into the same account and activate private synchronization there. **Sincronizar agora** must restore the same private data without a public profile. Each device has its own consent.
3. Remove only USB forwarding (`adb reverse --remove tcp:55474`), create/edit a visit/review or favourite, then force-stop/reopen. Records and pending changes must remain available. Restore with `adb reverse tcp:55474 tcp:55474`; use **Sincronizar agora** or wait for the pending retry. The other device receives the changes on resume/manual synchronization.
4. Edit the same review independently on both devices before synchronizing. Confirm that a conflict retains your local text and shows the account version. Explicit resend, correction or **Usar dados da conta e arquivar alteração** must preserve original input in the local archive. Repeat with a stale visit deletion while the other device changes its review.
5. Pause synchronization, make another change and verify it stays local/pending. Reactivate and verify convergence. Logout and sign into another account: it must never display the first account's records. Return to the original account and check both data and pending changes. Restart again to exercise Android Keystore restoration.

The integration suite automates these scenarios with two independent SQLite stores and profile-free Auth users. Physical touchscreen, Keystore and actual phone offline behavior still require owner acceptance. The ordinary unconfigured GitHub APK remains unconfigured; no managed Supabase project is used.


A2 update executed on 2026-11-27: SM A166B reports `0.1.0-alpha-a2.1023` / code 1023. The existing certificate was checked before building and against the installed APK, the universal AOT/non-debuggable release was verified (59,411,322 bytes), and `adb install -r` returned Success. First installation remains `2026-11-26 22:40:55`; only the update timestamp changed. USB `tcp:55474` forwarding is present and Android accepted the launch. This demonstrates update compatibility, not byte-level inspection of private SQLite/Keystore storage or physical acceptance. No domain-upload consent was enabled on the owner's behalf.


## A3 installed private alpha and acceptance

A3 replaces the historical A2 enable/pause controls. On each unaccepted account/device, the app explains automatic storage of existing and new private account data before any transfer. Accept offline or log out and browse the catalogue without an account. Existing A2 storage consent is retained; no acceptance was clicked automatically during installation. Guest archives and examples remain excluded.

The final `0.1.0-alpha-a3.1023` / code 1023 was installed on SM A166B with `adb install -r` (Success), using the existing package and verified original certificate. App ID 10419 and first installation `2026-11-26 22:40:55` are unchanged. The app launches, and screen inspection shows retained personal records/favourites with explicit private labels. This does not establish byte-level SQLite/Keystore preservation or full physical acceptance.

Private APK: `/tmp/bath-auth-acceptance-0m55gulo/bath-royale-alpha-a3.apk` (59,608,574 bytes). SHA-256: `711d0e7af6d5c7d2f29a9860cc279e218baa502bca9b17293982c84a8b3172a9`. Do not publish it. The update-only installer now uses `alpha-a3`, preserves the installed code/certificate, and never uninstalls or clears data. The retained local Auth database received the verified additive A3 migration; disposable community/protocol tests use separate stacks and are stopped.

Physical owner checks:

1. Confirm retained visits/reviews/favourites and account restoration. An unaccepted account must show storage disclosure before upload; accepting must permit offline use. Previously accepted A2 accounts synchronize automatically. There are no normal enable/pause controls.
2. Log out and use **Explorar catálogo sem conta**. Cached catalogue/details/rankings must remain readable; personal writes require login. Empty shared content should not be confused with archived guest examples.
3. Use **Adicionar trono** to contribute explicitly public content. After synchronization it becomes usable without a manual refresh. Duplicate names must be rejected safely; correct or archive the queued contribution through synchronization recovery. Pending contributions cannot collect visits.
4. An existing private record remains labelled **Privado · por associar ao catálogo**. Explicitly associate only the same actual place; the original visits/reviews/favourites must remain, and nothing is published by linking. Associations are immutable in this alpha.
5. Choose a public username in Profile. In a personal visit/experience, explicitly publish its review. A second account/anonymous browser sees the username, scores, tags and comment, with no visit ID/date, favourites or email. Edit or withdraw the published review and check the refreshed community ranking. Pending offline withdrawal takes effect when delivered.
6. Report public content. Ordinary accounts must be denied moderation access; a separately provisioned test moderator can hide/restore it. Hiding must remove community scores while retaining personal history.
7. Remove only `tcp:55474` forwarding, restart/use the app offline, then restore forwarding. Cached catalogue and private records must survive; pending changes retry safely. Exercise logout/relogin and A/B isolation without uninstalling or clearing storage. Keystore, touchscreen/keyboard and genuine two-human-device acceptance remain pending.

See [A3 architecture and executed verification](backend/community-alpha.md). Remote hosting/registration restrictions remain a separate release gate. No managed project, paid service, A4 or A5 was introduced.

## A3.1 development build and acceptance

The private alpha target remains `tool/auth_device_preview.dart` → owner `auth` backend over TLS/USB **55474**. The separately compiled fictional development target is `tool/local_development.dart` → **fixtures** backend over TLS/USB **55504**. Both retain the package and original signing certificate, but Auth sessions/account files/public caches are isolated by backend environment. A development replacement does not import or upload the owner's alpha data. Returning to the alpha target restores its original account namespace.

The owner explicitly approved replacing the installed A3.1 alpha with development. SM A166B now runs `0.1.0-dev-a31.1023`, code 1023, app ID 10419, original first-install time `2026-11-26 22:40:55`. Update/launch succeeded without uninstalling, clearing data or changing signing identity. Anonymous catalogue/navigation/details and the five-account selector were inspected on the phone. Actual SQLite/Keystore bytes are not claimed inspected.

Private workstation directory: `/home/samuel/.local/state/bath-royale-a31-development`. Its `test-accounts.txt` contains the requested fictional email/password reference; `development-defines.json` contains the generated development-only credential payload. It also retains signed alpha/development APKs and hash/verification JSON. Do not commit, upload or distribute these files. See [fixture preparation and isolation](backend/community-simplification.md#isolated-development-fixtures).

When an update is wanted, keep the phone connected, start the appropriate existing backend/gateway and use the matching configuration and original key:

```sh
python3 tool/install_private_alpha.py --development --config-dir /home/samuel/.local/state/bath-royale-a31-development --keystore /path/to/original/debug.keystore
```

Omit `--development` and use the owner's alpha TLS directory for the alpha target. The installer checks the existing certificate, preserves the installed version code and validates the selected endpoint/target before building. Never use a generated replacement signing key or uninstall to work around a mismatch. Existing accepted storage preferences are retained; new/unaccepted account stores still require the storage explanation to be accepted by the tester.

Concise physical acceptance:

1. While signed out, browse **Explorar**, **Rankings** and details; there should be no personal destinations, favourites or visits tab. Open **Conta** and tap a fictional account to sign in. Accept storage only after reading its concise notice/privacy link. No username setup is needed.
2. Use **novato** for an empty personal account, **cavaleiro** for repeated visits/history and **escudeiro** for lighter activity. Confirm the private email in Profile/Settings. Settings provides the same test-account selector when no editor/persistence failure blocks switching.
3. Tap **Avaliar**, choose a bathroom and read the anonymous-public submission disclosure. Save a fictional review, switch accounts and confirm it appears anonymously in community scores. Exact dates/favourites remain personal. Edit/delete your own review and verify public updates; historical private records must remain in Settings recovery only.
4. **duque** can create a bathroom via the separate entitled action; ordinary accounts cannot. **rei** can grant that entitlement and moderate a reported review in Settings. Revocation is supported by the protected API; its UI remains a later refinement. No review needs pre-approval.
5. Disconnect only fixture forwarding (`adb reverse --remove tcp:55504`), restart, browse the cache and submit a fictional review offline. Reconnect (`adb reverse tcp:55504 tcp:55504`), foreground the app or pull to refresh, and verify one eventual submission. Check account switching and secure restoration without clearing data.

Owner touchscreen/keyboard/offline/Keystore acceptance is pending. Future power-up rules and production privacy/registration/hosting decisions remain open. A4 visual redesign and A5 remain deferred.
