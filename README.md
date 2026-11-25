# Bath Royale

Bath Royale is a light-hearted bathroom discovery and rating app, starting with the University of Aveiro. Its goal is to help people find useful facilities, share reviews and build a personal collection, with rankings and community features to follow. See [VISION.md](VISION.md) and [ROADMAP.md](ROADMAP.md) for the intended direction.

## Current state

This is an early local Flutter prototype. It displays sample bathrooms, rating descriptions and filters, allows toggling favourites in memory, and supports light and dark themes. Rankings and profile are placeholders. Data is not persisted; reviews, bathroom creation and details are not yet implemented. The app currently uses Dart, Provider and Material 3.

## Development setup

The repository includes a Nix flake and direnv configuration for an `x86_64-linux` development shell. Install Nix with flakes enabled and direnv with its shell integration, then from the project directory run:

```sh
direnv allow
flutter --version
flutter pub get
```

Alternatively, enter the shell with `nix develop` and run the Flutter commands there. The flake lock pins the Nix input; `pubspec.lock` records Dart package versions. The configured environment has been used with Flutter 3.50.1 and Dart 3.14.0. Other platforms and toolchain versions may require additional setup. The flake provides Linux desktop dependencies, not an Android SDK or deployment configuration.

## Run, check and build

From the development shell:

```sh
flutter devices
flutter run -d linux
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build linux --debug
flutter build linux --release
```

 Linux builds require a working Linux desktop toolchain. Android and web release preparation is planned, and platform-specific prerequisites must be configured separately. Generated outputs under `build/` are not source files.

See [AGENTS.md](AGENTS.md) for development and Git practices.

## Material library migration

Flutter 3.50 deprecates the bundled `package:flutter/material.dart` in favour of the standalone `material_ui` package. The existing app still uses the bundled library, so analysis reports deprecation notices. The [Flutter migration guide](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui) describes compatibility bridges needed when dependencies still use the bundled widgets. Migrate and verify the app and its `flutter_rating_bar` dependency together in a separate change to preserve the current appearance.
