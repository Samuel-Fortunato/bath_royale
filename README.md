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

The `test` directory does not exist yet; add it as automated tests are introduced, and omit it from the formatting command until then. `flutter test` requires tests to be added first. Linux builds require a working Linux desktop toolchain. Android and web release preparation is planned, and platform-specific prerequisites must be configured separately. Generated outputs under `build/` are not source files.

See [AGENTS.md](AGENTS.md) for development and Git practices.
