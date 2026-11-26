# Private Android authentication preview

The ordinary GitHub APK is intentionally **guest-only**: its `lib/main.dart` build has no `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`. Do not add a development endpoint, CA, signing material or Auth credentials to that workflow or publish the APK described here. Backend deployment and public email delivery remain separate approval gates. This procedure uses only the independent `bath-royale-poc-auth` installation, fictional accounts, local mail capture and USB. It never needs the existing managed project, a paid service, a domain or a public listener.

## HTTPS without a public deployment

`tool/auth_device_preview.dart` is a separate, explicitly selected entry point. It accepts only `https://localhost:55474` and the placeholder `local-device-client`. The direct isolated Auth server does not require a gateway API key; this placeholder conveys no elevated privilege and must never be substituted for a managed project's secret/service-role key.

The target uses a fresh Dart `SecurityContext` containing only the supplied short-lived localhost certificate. Certificate trust, hostname and expiry validation stay enabled; there is no `badCertificateCallback`, HTTP exception or OS-wide CA installation. See Dart's [custom trusted certificate support](https://api.dart.dev/dart-io/HttpClient-class.html) and [SecurityContext](https://api.dart.dev/dart-io/SecurityContext-class.html). The public certificate alone enters the APK. Its private key stays on the development computer outside the checkout. The ordinary app entry point never imports this target or changes its platform TLS trust.

`tool/auth_device_proxy.py` terminates TLS exclusively on computer loopback port 55474 and proxies `/auth/v1/` to the independent Auth listener on 127.0.0.1:55471. It exposes no REST/database endpoint and prints no requests or tokens. `adb reverse` carries the phone's localhost connection over USB. Unplugging USB or removing that forwarding disconnects Auth. This is a local transport test, not evidence of production HTTPS or email delivery.

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

The backend remains rootless, with independent state/credentials/volumes/network and loopback-only bindings. Confirmation remains required; Mailpit is available on the computer at `http://127.0.0.1:55473`; optional USB forwarding below also makes it available on the authorized phone. Do not expose Auth or Mailpit to the LAN. Starting/stopping this instance does not select a managed Supabase project.

## Build, verify and install locally

```sh
flutter pub get --enforce-lockfile
BATH_DEVICE_TLS_DIRECTORY="$device_dir" flutter test --no-pub test/device_preview_test.dart
BATH_REAL_AUTH=1 BATH_DEVICE_TLS_DIRECTORY="$device_dir" flutter test --no-pub test/real_auth_test.dart
flutter build apk --release --no-pub --target tool/auth_device_preview.dart \
  --dart-define-from-file="$device_dir/defines.json" \
  --build-number "$device_code" --build-name "0.1.0-auth-local.$device_code"
python3 tool/verify_preview.py apk build/app/outputs/flutter-apk/app-release.apk \
  "$device_code" "0.1.0-auth-local.$device_code"
cp build/app/outputs/flutter-apk/app-release.apk "$device_dir/bath-royale-auth.apk"
adb install -r "$device_dir/bath-royale-auth.apk"
```

The verifier checks `com.example.bath_royale`, exact version, existing certificate, non-debuggable universal AOT payload and absence of the debug kernel. Never upload this private APK to GitHub Releases or replace the ordinary public preview. Build from a reviewed commit and record its SHA, version, certificate and checksum with your test notes. Installing with `-r` preserves app storage; actual preservation still needs the checks below. If installation fails, stop without uninstalling. To return to the public preview, first finish/cancel editors and log out, then install the guest-only APK with the same certificate and an equal or higher code.

For Linux compilation of the same device target:

```sh
flutter build linux --release --no-pub --target tool/auth_device_preview.dart \
  --dart-define-from-file="$device_dir/defines.json"
```

Use a working unlocked desktop Secret Service when executing it. This build command alone does not verify the desktop keyring lifecycle.

## Exercise the flows

Use new fictional emails such as `device-trono@example.com` and passwords used nowhere else. Profile now separates login, registration, confirmation, recovery-code validation and password change. Private email identifies the selected account; account UUIDs are not presented as profile information. The email is sent privately to the isolated Auth service; no public profile or domain records are uploaded.

For convenient phone confirmation/recovery, run the private inbox helper in a separate terminal and forward its loopback port over USB:

```sh
python3 tool/auth_device_mail.py
adb reverse tcp:55475 tcp:55475
adb reverse tcp:55473 tcp:55473
adb shell am start -a android.intent.action.VIEW -d http://localhost:55475
```

In the phone browser, open **http://localhost:55475**, enter the same fictional email used in the app, and choose **Atualizar mensagens**. The newest matching message appears first with **Copiar ligação para a app**. Return to Bath Royale, choose **Já recebi o email de confirmação** (or **Já tenho um código de confirmação**), paste into **Código ou ligação do email**, and choose **Confirmar email**. For recovery, use **Já tenho um código de recuperação**, paste the newest recovery link and choose **Validar recuperação**, then set a new password.

The helper reads only the isolated Mailpit API, filters recipients, maps links automatically and never opens/consumes them. It does not send email, store tokens, log requests, include external resources or expose a LAN listener. The page has no-store/referrer restrictions and a manual copy fallback if browser clipboard access is unavailable. Its full-Mailpit link uses the optional 55473 forwarding. Auth itself remains on the separately validated HTTPS connection; this local inbox introduces no app/OS trust relaxation.

Manual fallback: The direct Auth service's captured verification links start with `http://127.0.0.1:55471/verify?`. Before pasting one into the app, replace **only that prefix** with `https://localhost:55474/auth/v1/verify?`, retaining the token/query exactly. This maps the direct test server to the local gateway origin accepted by the adapter. Do not open the link in the browser first: that can consume the token. Use the newest matching confirmation/recovery message. Never paste tokens into logs, issues or test reports. A template containing a numeric OTP can instead be used directly with the matching email.

Record pass/fail separately for each physical check:

| Check | Expected behavior |
| --- | --- |
| In-place update | Existing guest bathrooms, visits, reviews, favourites and theme remain; fictional sample labels remain accurate. |
| Registration/confirmation | Login is rejected before confirmation; confirmation opens an empty isolated account. Guest records are not imported. |
| Secure restart | Force-stop/reopen restores the selected account and private email, without password entry. |
| Offline expiry/reconnection | Remove forwarding with `adb reverse --remove tcp:55474`, wait beyond the local 60-second JWT lifetime, force-stop/reopen and use local account data. Restore forwarding; renewal resumes without visible state churn every 15 seconds. |
| Logout/relogin | Logout returns to the original guest file; restarting stays guest. Relogin restores the original account's committed local data. |
| Second fictional account | Log out, register/confirm another account, verify it starts empty and cannot see the first account or guest records. |
| Recovery | Request recovery, copy the newest email token/link, validate it, choose a new password, then log out and log in with it. Recovery intent survives account-tree replacement and restart. |
| Drafts/failed commits | Finish/cancel editors before switching. After auth loss, reauthenticate to the original account to recover retained work; another account cannot see it. Memory-only drafts cannot survive process death. |
| Screen/keyboard | Check password visibility, keyboard, small screen, large text and all flows without overflow or inaccessible actions. |
| Remote revocation | Revoke only the fictional test account's Auth session in the isolated backend; the next due renewal hides its account. Restart must not restore that invalidated identity. |
| Secure-storage failures | Verify real platform behavior only in a controlled test setup. Automated failure injection covers failed deletion/write/guard access; it does not prove Android Keystore behavior. Do not wipe the app/key store to simulate an error on a data-preservation installation. |

For a controlled fictional revocation, the following touches only the explicitly named isolated container (replace the fictional email if necessary):

```sh
podman exec bath-royale-poc-auth-db psql -X -U supabase_admin -d postgres \
  -v ON_ERROR_STOP=1 -c "DELETE FROM auth.sessions WHERE user_id IN (SELECT id FROM auth.users WHERE email = 'device-trono@example.com');"
```

Environment isolation uses the complete configured URL. This local target has its own environment namespace and must not be pointed at another backend by editing its fixed URL. General account/environment separation also has automated regressions; physical multi-environment acceptance remains open.

## Stop and record limits

Stop the gateway with Ctrl-C, then:

```sh
adb reverse --remove tcp:55474
POC_INSTANCE=auth nix develop .#backend --offline --no-write-lock-file --command python3 backend/poc.py stop
```

Keep the isolated backend data and the original signing-key backup. Remove the private temporary device directory only when its test APK/certificate are no longer needed. Regenerating a certificate requires rebuilding the local target; it does not require clearing phone data.

## Prepared physical session — 2026-11-26

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
