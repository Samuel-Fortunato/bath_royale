# Bath Royale

**[📲 Descarregar APK Android de desenvolvimento](https://github.com/Samuel-Fortunato/bath_royale/releases)** — abre o pré-lançamento pretendido e transfere `bath-royale.apk` nos Assets. [Instruções de instalação](docs/android-previews.md).

Bath Royale is a light-hearted bathroom discovery and rating app, starting with the University of Aveiro. Its goal is to help people find useful facilities, share reviews and build a personal collection, with rankings and community features to follow. See [VISION.md](VISION.md) and [ROADMAP.md](ROADMAP.md) for the intended direction.

## Current state

This is an early local Flutter prototype. It displays sample bathrooms, rating descriptions and filters, allows toggling favourites, and supports light and dark themes. Personal/community rankings and a visit-based collection are available; a local profile provides favourites and recent activity. Local SQLite storage preserves data and theme settings across restarts. See [storage architecture](docs/storage.md). Bathroom entities, individual reviews and personal favourites/visits are separate records, with multiple reviews per bathroom and distinct personal and community ratings. Bathroom details now show community averages, individual reviews and personal history, with validated review creation/editing, favourites and explicit visit recording. The + action creates bathrooms with validated names and duplicate protection. Explore supports name search, community/personal/name/latest-visit sorting, result counts, empty states and clearing search/filters. See [the local data model](docs/data-model.md) for ownership, visit and aggregate semantics. The app currently uses Dart, Provider and Material 3.

## Development setup

The repository includes a Nix flake and direnv configuration for an `x86_64-linux` development shell, shared with GitHub Actions. Install Nix with flakes enabled and direnv with its shell integration, then from the project directory run:

```sh
direnv allow
flutter --version
flutter pub get
```

Alternatively, enter the shell with `nix develop` and run the Flutter commands there. The flake lock pins the Nix input; `pubspec.lock` records Dart package versions. The configured environment has been used with Flutter 3.50.1 and Dart 3.14.0. Other platforms and toolchain versions may require additional setup. The flake provides Linux desktop dependencies and an Android SDK/NDK with Java 17; see the Android instructions below. Android development previews use the existing signing key through GitHub Actions secrets. Production signing and store deployment remain open.

## Run, check and build

From the development shell:

```sh
flutter devices
flutter run -d linux
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
dart run tool/check_analysis.dart
flutter test
flutter build linux --debug
flutter build linux --release
```

Linux builds require a working Linux desktop toolchain. Android production and web release preparation remain planned. Generated outputs under `build/` are not source files.

## Android preview downloads

Pushes to `main` and manual runs execute formatting, a strict analysis policy for the documented Material debt, tests and an Android debug APK build in the locked Nix environment. Download the APK from a successful [Android preview run](https://github.com/Samuel-Fortunato/bath_royale/actions/workflows/android-preview.yml); artifacts are kept for 14 days. Manual runs can optionally publish a [GitHub pre-release](https://github.com/Samuel-Fortunato/bath_royale/releases) with a direct APK download.

On your phone, extract the artifact ZIP, open the APK and choose **Update**. Keep the existing app installed to preserve its local data. See [phone installation, signing, versioning and CI details](docs/android-previews.md). These are development previews; production signing is separate. Phase 2 backend work has not started.

See [AGENTS.md](AGENTS.md) for development and Git practices.

## Material library migration

Flutter 3.50 deprecates the bundled `package:flutter/material.dart` in favour of the standalone `material_ui` package. The existing app still uses the bundled library, so analysis reports deprecation notices. The [Flutter migration guide](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui) describes compatibility bridges needed when dependencies still use the bundled widgets. Migrate and verify the app and its `flutter_rating_bar` dependency together in a separate change to preserve the current appearance.

## Android on NixOS

Enter the project environment with `direnv exec .` or `nix develop`. The flake supplies Android platforms 35 and 36, Android CMake 3.22.1, build tools 36.0.0, NDK 28.2.13676358 and Java 17, accepts the Android SDK licence, and sets the SDK/NDK/Java environment variables. The SDK is immutable in the Nix store; add SDK components through the flake rather than using SDK Manager to write there.

The Android build follows the locally installed Flutter 3.50.1 templates: Gradle 9.5.0, Android Gradle Plugin 9.3.1, Kotlin Gradle Plugin 2.4.20 and Java/JVM target 17. App Kotlin uses the top-level `kotlin.compilerOptions` block. The template's `android.builtInKotlin=false` and `android.newDsl=false` compatibility flags remain enabled as opt-outs; do not remove them independently of a Flutter template migration. The application ID remains `com.example.bath_royale`.

```sh
direnv exec . flutter build apk --debug
```

The flake sets `android.aapt2FromMavenOverride` via `GRADLE_OPTS` to the Nix-provided `aapt2`. This avoids executing the generic Linux Maven binary on NixOS. Local SDK paths, signing files, caches and generated Android build directories are ignored by Git. Dependency validation remains enabled. Release signing remains separate work.

Verified on 2026-11-25: `flutter build apk --debug` produced `build/app/outputs/flutter-apk/app-debug.apk`; inspecting the APK confirmed the existing application ID, SDK 36 and ARM32/ARM64/x86_64 libraries. All 16 tests, Dart formatting and `git diff --check` passed. Analysis reports only the 12 documented Material import deprecation notices (exit status 1). The first sandboxed build could not write Flutter SDK telemetry; rerunning with cache access succeeded. No dependency-validation bypass was used. The owner has run the app on a physical Android phone. This milestone also successfully launched and synchronized the updated app on SM A166B with a connected Dart VM service; Android release builds remain unverified.

Phase 1 local prototype acceptance is recorded in [the stabilization audit](docs/phase-1-audit.md), including verification results and deferred technical debt.

## UI/UX redesign

The approved [specification](docs/bath-royale-design/ui-design.md) and [interactive reference](docs/bath-royale-design/ui-reference.html) define three sessions before Phase 2. Session 1 implements the contextual shell, Profile → Settings theme control, compact Explore cards with community/personal distinctions and a single filter panel, favourite hearts, and independent bathroom Summary/Reviews/Personal Visits tabs. Visit registration remains immediate; dismissing its invitation keeps the visit, while the separate undo action uses existing safety checks. The review form, collection, rankings and broader profile redesign remain later sessions. See [milestones and outstanding phone acceptance](ROADMAP.md#phase-16--approved-uiux-redesign-before-phase-2).
