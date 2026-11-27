# Android previews and CI

A5.3 delivers the managed initial alpha, with owner-confirmed physical acceptance and separately authorized publication. See [actual managed acceptance and publication](backend/managed-alpha-acceptance.md). Second physical device testing remains pending. CI validates unconfigured builds without uploading or publishing development APKs. Configured publication requires the explicitly approved gate; close it after an authorized release to keep subsequent routine pushes validation-only.

Public semantic versions and internal Android build codes are documented in [release presentation and historical review](releases/README.md).

## Download and install from a phone

1. Open [the initial alpha release](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/alpha-1039) and download **bath-royale.apk** under **Assets**. Use configured `alpha-` releases for the managed service; historical `preview-` releases are development builds. No GitHub login or ZIP extraction is needed for this public repository. `/releases/latest` excludes pre-releases and must not be used.
2. Open the APK. If Android asks, allow installation from that browser or Files app. Choose **Update** / **Atualizar**. Keep the existing app installed: uninstalling or clearing storage removes local data.
3. Optionally verify the download against the accompanying `SHA256SUMS` (`sha256sum -c SHA256SUMS` with both files in the same directory).
4. Open Bath Royale, register directly with email/password or sign in to your existing account, and save a recovery code in Settings. No invitation or email confirmation is required in this initial alpha; unverified email cannot recover your account. You can disable the installation permission afterwards.

Every `main` push or manual dispatch runs validation. Only an explicitly approved configured-alpha run uploads artifacts and publishes a pre-release. Releases persist until explicitly removed by a maintainer and are never marked as the latest stable production release. Configured Actions artifacts remain available for 14 days as an alternative ZIP download. Initial-alpha privacy/support/retention limitations are included in the release notes and in-app notice; the dedicated support contact and verified-email authentication/recovery remain mandatory before public launch.

If Android reports an incompatible app or refuses an update, do **not** uninstall it to get past the error. Check the package, signing certificate and version first. Preview APKs are optimized universal release builds (ARM32, ARM64 and x86_64), without debugging enabled. They retain the existing development certificate and are intended for trusted testing, independently of production store signing.

For isolated authentication development, use the separate [private Android Auth device procedure](android-auth-device-testing.md). Those local TLS/fixture APKs are never distributed by the release workflow. The approved alpha uses the managed HTTPS endpoint and public client key only; with the gate disabled, the ordinary workflow supplies no backend defines and distributes no APK.

## Reproducible verification

[The workflow](../.github/workflows/android-preview.yml) runs automatically on pushes to `main` and manually on `main`. It uses Ubuntu 24.04 and `nix develop --no-write-lock-file` with the committed `flake.lock`, rather than a separate Flutter setup action. The shared development shell supplies Flutter 3.50.1 / Dart 3.14.0, Java 17, Android platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. Gradle 9.5.0, AGP 9.3.1 and KGP 2.4.20 remain pinned in the Android project. `flutter pub get --enforce-lockfile` refuses package-lock drift.

Checks run before signing/building:

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_analysis.dart
flutter test --no-pub
actionlint
python3 -m unittest discover -s tool -p "test_*preview*.py"
```

The analysis helper runs `dart analyze --format=machine` across the project and prints all diagnostics. It accepts only the exact bundled-Material import notice in the explicit paths recorded in `tool/check_analysis.dart`. New imports, other informational diagnostics, warnings, errors, malformed output and analyzer failures fail CI. Regression tests exercise this policy. Nothing is suppressed in `analysis_options.yaml`; ordinary `flutter analyze` still reports the known debt. Remove the baseline as part of the separate Material migration.

GitHub Actions have immutable commit pins. The build job has only `contents: read`; only publication has `contents: write`. Checkout does not persist credentials. Dependency caches exclude signing files, app outputs and local data. Builds retain the existing 60-minute timeout. Each workflow run has a unique concurrency group with cancellation disabled: newer pushes cannot cancel another build/publication. Different version codes may finish out of order, so select the highest build number when updating. Manual cancellation can leave a draft; rerun the publication job to resume it.

The publisher verifies the downloaded artifact checksum, creates a unique lightweight `alpha-<version_code>` tag at the exact source SHA (historically `preview-<version_code>`), and prepares a draft pre-release. It downloads and compares uploaded assets byte for byte before publishing. Existing tags must match the source commit. A partially uploaded draft resumes only if existing assets match; uploads never use overwrite. An already published release succeeds idempotently only when both assets match; mismatches fail without changing it. No releases or tags are automatically deleted. If a full build rerun produces different bytes for the same version, publication fails safely: retry only the failed publication job with the original artifact, or start a new numbered workflow run. The publication job never compiles or receives signing material.

Local commands above assume the development tools are already on PATH (Codex is launched with `direnv exec . codex`). Fall back to `direnv exec . <command>` only when needed. Bubblewrap 0.12.0 is available; keep normal sandboxing enabled.

After pushing routine verified development work, report the CI URL and current status and finish without waiting. Wait for hosted CI only for CI/CD implementation or debugging, or an explicit owner request, unless the owner waives waiting. Local validation never proves remote checks passed.

## Signing and existing installations

Android updates require the same application ID and compatible signing key; version codes must not go backwards. See [Android app signing](https://developer.android.com/studio/publish/app-signing) and [versioning](https://developer.android.com/studio/publish/versioning).

During setup, the APK installed on the owner's SM A166B, the local debug APK and the existing local development key were inspected. They share package `com.example.bath_royale` and certificate SHA-256:

```text
4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc
```

The installed baseline has version name `0.1.0`, version code `1`, and is debuggable. With the owner's permission, the existing key was stored as repository Actions secret `ANDROID_PREVIEW_KEYSTORE_BASE64`. The workflow restores it into a private temporary `ANDROID_USER_HOME/debug.keystore`, sets `PREVIEW_KEYSTORE` explicitly for the release signing configuration, checks the certificate before compilation, uses Android's standard development alias/password (`androiddebugkey` / `android`), and removes it in an `always()` cleanup step. These are the standard debug defaults, not production signing credentials. The private key itself must never be printed, committed, included in caches or uploaded as an artifact. The committed certificate fingerprint is public and is checked on every built APK. A missing or different key fails the build; CI never silently generates an incompatible replacement.

Keep a secure backup of the original key outside Git. If the secret must be restored, use a trusted local terminal and pass the key directly to GitHub without printing it:

```sh
base64 -w 0 /path/to/existing/debug.keystore |
  gh secret set ANDROID_PREVIEW_KEYSTORE_BASE64 --repo Samuel-Fortunato/bath_royale
```

The repository's Actions workflows can access this secret; review workflow changes accordingly. Do not replace the key casually. A different development machine's generated key will not update these installations. Keep using the matching key for local `flutter run` on this phone as well. Production signing, Play distribution, identity changes and any migration from this debug key require a separate decision and data-preservation plan; they remain outside this milestone.

## Identity and versioning

The application ID stays `com.example.bath_royale`; no suffix or storage schema change is introduced. Each new workflow run uses version name `0.1.0-preview.<run_number>` and version code `1000 + run_number`, so CI previews advance beyond the installed code `1`. Rerunning the same run retains its version code; dispatch a new run for a new numbered preview. The artifact name includes the version code; the APK is always `bath-royale.apk`; the run summary records the source commit. Do not reset or rename this workflow's run-number sequence or introduce higher local build numbers without planning a new version-code floor. Future app version changes should update the workflow's version-name base together with `pubspec.yaml`.

Installing an older preview over a newer one may be rejected. Local development uses code `1` by default: after installing CI previews, use a local `--build-number` at least as high as the installed preview if Android rejects a downgrade. Never uninstall to solve a version conflict when local data matters.


## Verification record

Local verification on 2026-11-25: locked package resolution, formatting (36 files), strict analysis policy, all 40 tests, actionlint, Nix flake checks and the Android debug preview build passed. Ordinary `flutter analyze --no-pub` reports only the 20 documented Material notices (exit 1); the strict gate accepts these and no other diagnostics. Initial setup verified the existing phone/local certificate match and stored the approved signing secret.

[The first GitHub Actions run](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45604860872), from commit `58786e7`, succeeded on GitHub's hosted runner in 5m3s. It independently resolved the locked dependencies, passed checks and 40 tests, compiled the Android APK, verified package/version/certificate and uploaded `bath-royale-preview-1001` with its checksum. The generated version is `0.1.0-preview.1` / code `1001`. The optional pre-release job was correctly skipped on this push and has not been invoked; its workflow is linted, but publishing is not yet verified. The initial run's Node 20 action deprecation prompted an update to immutable pins for current Node 24 action releases.

[The second hosted run](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45605957997), from commit `a8a5fa5`, also completed successfully with the refreshed action pins. The CI/CD milestone remains complete; Phase 2 has not started.

Workflow refinement on 2026-11-25: routine preview cancellation and isolated publication concurrency were validated locally with actionlint and a concurrency scenario check. The owner waived waiting for hosted CI for this change; its remote outcome is not established by local checks.

An APK with matching identity, signing and an increasing version is eligible for an in-place Android update; actual preservation of this phone's data after installing a CI APK still needs a device update check. No CI APK has been installed on the owner's phone during setup.

Automatic publication update: local actionlint and mocked publication scenarios cover fresh publication, partial drafts, successful retries, conflicting tags/assets, corrupt checksums, incomplete published releases and interrupted uploads. [Hosted run 45724799545](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45724799545) passed both build and publication jobs, publishing [development pre-release 1015](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/preview-1015). Its tag points exactly to `3e81b3685ab94abdb44d3ff7dc01e290f26c1df6`. A publication-only hosted retry (attempt 2) also passed without compiling or overwriting assets. The publisher compared both remote assets against the original verified artifact.

Independent download verification on 2026-11-26: the public `bath-royale.apk` passes its accompanying checksum, `apksigner verify` confirms the existing certificate above, and `aapt` confirms `com.example.bath_royale`, code `1015`, name `0.1.0-preview.15`. APK SHA-256: `2e7bc705eb673e119fae1f1c6fbf6bc7ff0b8a51c52527e0b27fb76d86d61f7c`. No phone installation was performed. Initial hosted failures exposed checkout clearing downloaded artifacts and REST tag lookup excluding drafts; both were corrected and covered by regressions. The incomplete `preview-1014` draft/tag was deliberately retained rather than deleted automatically.

## Optimized preview maintenance (after Phase 2.3A)

The workflow builds `flutter build apk --release --no-pub` with unchanged version arguments. It does not split per ABI. Before compilation, `tool/verify_preview.py key` checks the existing private key certificate; missing, unreadable or incompatible material fails without generating a key. After compilation, `tool/verify_preview.py apk` verifies signature, package/version, absence of the debuggable flag, exactly ARM32/ARM64/x86_64, AOT libraries for each ABI and absence of a debug Dart kernel. Publication and checksum verification remain unchanged.

For a local equivalent, use the existing matching key (never create a replacement):

```sh
python3 tool/verify_preview.py key /path/to/existing/debug.keystore
PREVIEW_KEYSTORE=/path/to/existing/debug.keystore flutter build apk --release --no-pub --build-name 0.1.0-preview.N --build-number CODE
python3 tool/verify_preview.py apk build/app/outputs/flutter-apk/app-release.apk CODE 0.1.0-preview.N
```

Local `flutter run` and `flutter build apk --debug` remain supported. No SQLite schema, authentication or backend changes are part of this milestone.

Physical acceptance remains with the owner: install over the existing GitHub preview using **Atualizar**, confirm existing bathrooms, visits, reviews, favourites and theme remain, restart and check persistence, and smoke-test navigation and review editing. Do not uninstall or clear storage. Certificate/identity/version checks establish update eligibility, not proof that this phone's data survived.

Local verification on 2026-11-26: all 170 ordinary Flutter tests passed (one intentional real-suite placeholder skipped), locked dependency resolution, Dart formatting, unchanged strict analyzer gate, actionlint and five preview-tooling tests passed. The universal release is **56,837,554 bytes**, versus **157,023,093 bytes** for independently downloaded/checksummed debug preview 1023 (**63.80% smaller**). Its expected certificate, package, version 1024 / `0.1.0-preview.24`, non-debuggable status and three-ABI AOT payload passed verification. The ARM64-targeted comparison is **19,805,283 bytes** (ARM64 engine/AOT only; plugin libraries may retain other ABIs); it was not published.

[Hosted run 45859523546](https://github.com/Samuel-Fortunato/bath_royale/actions/runs/45859523546) for `854ba9b` completed successfully, including publication of [preview 1025](https://github.com/Samuel-Fortunato/bath_royale/releases/tag/preview-1025). Independently downloaded public assets passed `SHA256SUMS` and the same APK verifier: package `com.example.bath_royale`, code **1025**, name **0.1.0-preview.25**, expected certificate above, non-debuggable and universal three-ABI AOT release. Published size: **56,837,558 bytes**. The immediate predecessor, Phase 2.3A debug preview **1024**, finished publishing during this work: **157,025,741 bytes**, independently checksum-verified. Reduction against that predecessor: **63.8037%**. The unchanged certificate/package and increasing code (1024 → 1025) establish update compatibility eligibility. No physical in-place update was performed; existing phone data preservation remains unverified.

## Optional authentication configuration

Preview signing, universal release optimization and publication remain unchanged. With no public backend build configuration, previews continue in guest mode. See [authentication configuration and device acceptance](backend/production-authentication.md). Account sessions use Android Keystore-backed storage; backup is disabled to prevent credential export/restoration. Physical in-place update/data preservation and Android secure-storage lifecycle checks remain owner acceptance items.
