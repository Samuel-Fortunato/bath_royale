import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Non-secret write-ahead denial of offline credential restoration.
/// This stores only environment identifiers and booleans, never sessions.
abstract interface class RestorationGuard {
  Future<bool> isAllowed(String environment);
  Future<void> setAllowed(String environment, bool allowed);
}

class PlatformRestorationGuard implements RestorationGuard {
  final Future<Directory> Function() directory;
  const PlatformRestorationGuard({
    this.directory = getApplicationSupportDirectory,
  });

  Future<T> _access<T>(T Function(Database) action) async {
    final root = await directory();
    await root.create(recursive: true);
    final database = sqlite3.open('${root.path}/auth-restoration.sqlite3');
    try {
      database.execute('PRAGMA synchronous = FULL');
      if (database.userVersion == 0) {
        database.execute('BEGIN IMMEDIATE');
        database.execute('''CREATE TABLE restoration (
          environment TEXT PRIMARY KEY, allowed INTEGER NOT NULL CHECK (allowed IN (0, 1))
        )''');
        database.userVersion = 1;
        database.execute('COMMIT');
      } else if (database.userVersion != 1) {
        throw StateError('Unsupported authentication restoration schema');
      }
      return action(database);
    } finally {
      database.close();
    }
  }

  @override
  Future<bool> isAllowed(String environment) => _access((database) {
    final rows = database.select(
      'SELECT allowed FROM restoration WHERE environment = ?',
      [environment],
    );
    // Missing permission (including pre-hardening sessions) fails closed.
    return rows.isNotEmpty && rows.single['allowed'] == 1;
  });

  @override
  Future<void> setAllowed(String environment, bool allowed) => _access((
    database,
  ) {
    database.execute(
      'INSERT OR REPLACE INTO restoration (environment, allowed) VALUES (?, ?)',
      [environment, allowed ? 1 : 0],
    );
  });
}
