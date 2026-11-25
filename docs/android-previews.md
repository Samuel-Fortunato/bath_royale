# Android previews and CI

## Download and install from a phone

1. Open [Android preview runs](https://github.com/Samuel-Fortunato/bath_royale/actions/workflows/android-preview.yml) in your phone's browser and sign into GitHub. Select a successful run for `main`.
2. Under **Artifacts**, download `bath-royale-preview-<number>`. Extract the ZIP in the phone's Files app and open the `.apk` inside. Artifacts expire after 14 days; use a newer successful run if needed.
3. If Android asks, allow installation from that browser or Files app. Choose **Update** / **Atualizar**. Keep the existing app installed: uninstalling or clearing its storage removes the local SQLite database and settings.
4. Open Bath Royale and check that your bathrooms, visits, reviews and favourites remain available. You can disable the browser's installation permission afterwards.

For a direct APK link without extracting a ZIP, a maintainer can choose **Run workflow** on `main` and enable **Publish a GitHub pre-release**. Then open [Releases](https://github.com/Samuel-Fortunato/bath_royale/releases), select the desired preview and download its `.apk` from **Assets**. This repository is public, so published release APKs are public downloads. Automatic push builds only create workflow artifacts. Pre-releases are opt-in, persist until a maintainer deletes them, and are not marked as the latest production release. No pre-release is published as part of initial setup.

If Android reports an incompatible app or refuses an update, do **not** uninstall it to get past the error. Check the package, signing certificate and version first. Preview APKs are development/debug builds, with debug capabilities and larger downloads; they are intended for trusted testing, not store distribution.

## Reproducible verification

[The workflow](../.github/workflows/android-preview.yml) runs automatically on pushes to `main` and manually on `main`. It uses Ubuntu 24.04 and `nix develop --no-write-lock-file` with the committed `flake.lock`, rather than a separate Flutter setup action. The shared development shell supplies Flutter 3.50.1 / Dart 3.14.0, Java 17, Android platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. Gradle 9.5.0, AGP 9.3.1 and KGP 2.4.20 remain pinned in the Android project. `flutter pub get --enforce-lockfile` refuses package-lock drift.

Checks run before signing/building:

```sh
direnv exec . flutter pub get --enforce-lockfile
direnv exec . dart format --output=none --set-exit-if-changed lib test tool
direnv exec . dart run tool/check_analysis.dart
direnv exec . flutter test --no-pub
direnv exec . actionlint
```

The analysis helper runs `dart analyze --format=machine` across the project and prints all diagnostics. It accepts only the exact bundled-Material import notice in the 20 existing Phase 1 files. New imports, other informational diagnostics, warnings, errors, malformed output and analyzer failures fail CI. Regression tests exercise this policy. Nothing is suppressed in `analysis_options.yaml`; ordinary `flutter analyze` still reports the known debt. Remove the baseline as part of the separate Material migration.

GitHub Actions have immutable commit pins. The build job has only `contents: read`; only the optional pre-release job has `contents: write`. Checkout does not persist credentials. Pub and Gradle downloads are cached using toolchain/package/Gradle input hashes; signing files, app outputs and local data are excluded. Nix uses its standard binary cache. Cold runners can take longer to download the Android toolchain; the build job has a 60-minute timeout. Runs are serialized per branch without cancelling active builds. Workflow artifacts include the APK and `SHA256SUMS` with no additional ZIP compression.

## Signing and existing installations

Android updates require the same application ID and compatible signing key; version codes must not go backwards. See [Android app signing](https://developer.android.com/studio/publish/app-signing) and [versioning](https://developer.android.com/studio/publish/versioning).

During setup, the APK installed on the owner's SM A166B, the local debug APK and the existing local development key were inspected. They share package `com.example.bath_royale` and certificate SHA-256:

```text
4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc
```

The installed baseline has version name `0.1.0`, version code `1`, and is debuggable. With the owner's permission, the existing key was stored as repository Actions secret `ANDROID_PREVIEW_KEYSTORE_BASE64`. The workflow restores it into a private temporary `ANDROID_USER_HOME/debug.keystore`, uses Android's standard development alias/password (`androiddebugkey` / `android`), and removes it in an `always()` cleanup step. These are the standard debug defaults, not production signing credentials. The private key itself must never be printed, committed, included in caches or uploaded as an artifact. The committed certificate fingerprint is public and is checked on every built APK. A missing or different key fails the build; CI never silently generates an incompatible replacement.

Keep a secure backup of the original key outside Git. If the secret must be restored, use a trusted local terminal and pass the key directly to GitHub without printing it:

```sh
base64 -w 0 /path/to/existing/debug.keystore |
  gh secret set ANDROID_PREVIEW_KEYSTORE_BASE64 --repo Samuel-Fortunato/bath_royale
```

The repository's Actions workflows can access this secret; review workflow changes accordingly. Do not replace the key casually. A different development machine's generated key will not update these installations. Keep using the matching key for local `flutter run` on this phone as well. Production signing, Play distribution, identity changes and any migration from this debug key require a separate decision and data-preservation plan; they remain outside this milestone.

## Identity and versioning

The application ID stays `com.example.bath_royale`; no suffix or storage schema change is introduced. Each new workflow run uses version name `0.1.0-preview.<run_number>` and version code `1000 + run_number`, so CI previews advance beyond the installed code `1`. Rerunning the same run retains its version code; dispatch a new run for a new numbered preview. The artifact/APK name includes the version code; the run summary records the source commit. Do not reset or rename this workflow's run-number sequence or introduce higher local build numbers without planning a new version-code floor. Future app version changes should update the workflow's version-name base together with `pubspec.yaml`.

Installing an older preview over a newer one may be rejected. Local development uses code `1` by default: after installing CI previews, use a local `--build-number` at least as high as the installed preview if Android rejects a downgrade. Never uninstall to solve a version conflict when local data matters.

Optional release tags are unique `preview-<version_code>` tags pointing at the exact successful build commit. Publishing an already existing tag fails rather than replacing downloads. Start a new manual run to publish a new preview. The pre-release job downloads the already verified artifact; it does not rebuild or receive the signing key.

## Verification record

Local verification on 2026-11-25: locked package resolution, formatting (36 files), strict analysis policy, all 40 tests, actionlint and the Android debug preview build passed. Ordinary `flutter analyze --no-pub` reports only the 20 documented Material notices (exit 1); the strict gate accepts these and no other diagnostics. Initial setup verified the existing phone/local certificate match and stored the approved signing secret. GitHub Actions verification is pending the initial push. An APK with matching identity, signing and an increasing version is eligible for an in-place Android update; actual preservation of this phone's data after installing a CI APK still needs a device update check.
