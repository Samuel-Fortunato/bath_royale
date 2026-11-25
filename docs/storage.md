# Local storage

## Choice

The app uses SQLite through `sqlite3` 3.x, plus `path_provider` for the private application support directory and `uuid` for newly created bathroom, visit and review IDs. Versions and transitive dependencies are locked in `pubspec.lock`. SQLite's native assets are bundled into Linux and Android builds; no device SQLite installation is required.

Drift was evaluated: it adds typed queries, reactive streams, code generation and migration tooling, and supports native SQLite and browser WebAssembly. For this small Provider-based prototype, explicit SQL keeps the storage adapter small and avoids a second reactive model and code-generation workflow. `sqflite` would need a separate desktop implementation. Key/value or JSON files would require implementing relational constraints and atomic multi-record writes ourselves.

References: [sqlite3 installation and platforms](https://pub.dev/packages/sqlite3), [Drift native support](https://drift.simonbinder.eu/platforms/vm/), [Drift web requirements](https://drift.simonbinder.eu/platforms/web/).

## Architecture and durability

`LocalStore` contains SQL and serialization; domain state has no UI dependency. Production bootstrap opens `bath_royale.sqlite` in the platform application support directory. Tests pass memory connections or unique temporary files and never call the production opener. The loading screen precedes state restoration. Initial sample data and the initialization marker commit together; an initialized empty database remains empty. Deleted records are never seeded again.

Each state mutation writes a complete normalized snapshot within `BEGIN IMMEDIATE`/`COMMIT`. A failed write rolls back to the last committed snapshot. This synchronous approach is intentionally bounded to the small local prototype and one running application instance. Incremental writes and an isolate should replace snapshot writes before larger datasets or background synchronization are introduced. Readers see only complete database transactions.

Write failure preserves the unsaved in-memory state, blocks further UI interaction and offers retry; the previous committed database remains intact. The screen explicitly warns that the process must remain open until retry succeeds. Startup errors, invalid serialized records, failed integrity checks and unsupported future schema versions produce a retry screen without resetting or deleting the database. There is no automatic destructive recovery. For manual recovery, preserve the original database file and any SQLite journal alongside it before attempting repairs.

## Schema and migration

SQLite foreign keys are enabled on every connection. Tables store bathrooms, visits, reviews, favourites, initialization metadata and settings. Reviews have a unique visit reference and a composite foreign key `(visit, bathroom, author)` matching `(id, bathroom, user)` on visits. Ratings, category bounds, timestamp ordering and boolean settings have database checks. IDs, normalized bathroom names, visit tuples and favourite pairs have uniqueness constraints. Ownership of mutations is additionally enforced by `AppState`; this is local integrity, not authentication.

Schema version is `PRAGMA user_version = 2`. The retained v1 schema defines entities and metadata; v2 adds theme settings with the previous dark-theme default. Fresh databases and migrations run transactionally. Migration fixtures verify preserving v1 records. Unknown nonempty unversioned databases and versions newer than the application are refused. Future changes must add explicit ordered migrations and tests using previous-version fixtures. Destructive future migrations should first create a recoverable backup and define conversion/recovery steps; never recreate a database as an error fallback.

Timestamps use UTC microseconds since epoch; tags are serialized JSON within review rows. Existing sample IDs remain stable, while new entity IDs are UUID v4 values. UUIDs allow independent creation without timestamp/counter collisions and can be carried to a community backend. They do not solve authentication, conflict resolution, deletions/tombstones or synchronization; those require a separate design before Phase 2.

The most recent personal rating follows visit time, then visit ID for deterministic ties, including reviews submitted later for older visits. Rapid registration of the same bathroom within 800 ms reuses the last visit when timestamps are also within that interval. Later repeat visits remain valid. Exact duplicate timestamps are still constrained by SQLite. The review form's save guard and atomic visit/review operation avoid duplicate submission.

## Platforms and development

Linux and Android are the current production targets. The project flake includes Android SDK platforms 35 and 36 and Android CMake 3.22.1 for the current path-provider/JNI dependency. No global Nix configuration is changed. Native SQLite is supplied by package build hooks.

Future web support requires replacing the native opener with a WebAssembly/OPFS or IndexedDB adapter (and browser storage failure handling). Neither `dart:io` nor the current native opener is a web implementation. The normalized schema and domain records can be retained; web hosting headers, worker assets, browser persistence and multi-tab behavior must be verified separately.

## Verified checks

All 29 automated tests pass, including the existing behavior suite and isolated storage/UI tests. Formatting and Linux/Android debug compilation pass. Analysis exits with 16 Material import deprecation notices and no other diagnostics. Initial Android builds exposed missing SDK 35 and CMake 3.22.1; both are now supplied reproducibly by the flake.
