import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../models/bathroom.dart';
import '../models/bathroom_activity.dart';
import '../models/review.dart';
import '../models/visit.dart';

class LocalData {
  final List<Bathroom> bathrooms;
  final List<Visit> visits;
  final List<Review> reviews;
  final List<BathroomActivity> favourites;
  final bool darkMode;
  LocalData({
    required this.bathrooms,
    required this.visits,
    required this.reviews,
    required this.favourites,
    required this.darkMode,
  });
}

/// Owns one connection. Tests supply an in-memory or temporary database.
class LocalStore {
  final Database database;
  LocalStore(this.database) {
    try {
      database.execute('PRAGMA foreign_keys = ON');
      if (database.select('PRAGMA quick_check').single.values.single != 'ok') {
        throw StateError('Database integrity check failed');
      }
      final version = database.userVersion;
      if (version > 3) {
        throw StateError('Database was created by a newer application');
      }
      transaction(() {
        if (version == 0) {
          if (database
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .isNotEmpty) {
            throw StateError('Unrecognized database; no data was changed');
          }
          database.execute(schemaV1);
        }
        if (version < 2) {
          database.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), dark_mode INTEGER NOT NULL CHECK(dark_mode IN (0,1)))',
          );
          database.execute('INSERT INTO settings VALUES(1,1)');
          database.userVersion = 2;
        }
        if (version < 3) {
          database.execute(
            "ALTER TABLE bathrooms ADD COLUMN emoji TEXT NOT NULL DEFAULT '🚽' CHECK(length(emoji)>0)",
          );
          database.execute(
            'ALTER TABLE bathrooms ADD COLUMN accent INTEGER NOT NULL DEFAULT 0 CHECK(accent BETWEEN 0 AND 5)',
          );
          for (final row in database.select('SELECT id,name FROM bathrooms')) {
            final id = row['id'] as String;
            final b = Bathroom(
              id: id,
              name: row['name'] as String,
              createdBy: 'migration',
            );
            database.execute(
              'UPDATE bathrooms SET emoji=?,accent=? WHERE id=?',
              [b.emoji, b.accent, id],
            );
          }
          database.userVersion = 3;
        }
      });
      if (database.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw StateError('Broken database references');
      }
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  // Version 1 is retained as an executable migration fixture.
  static const schemaV1 = '''
CREATE TABLE metadata (id INTEGER PRIMARY KEY CHECK(id=1), initialized INTEGER NOT NULL CHECK(initialized=1));
CREATE TABLE bathrooms (id TEXT PRIMARY KEY NOT NULL CHECK(length(id)>0), name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE, creator TEXT NOT NULL CHECK(length(creator)>0));
CREATE TABLE visits (id TEXT PRIMARY KEY NOT NULL CHECK(length(id)>0), bathroom TEXT NOT NULL REFERENCES bathrooms(id), user TEXT NOT NULL CHECK(length(user)>0), at INTEGER NOT NULL, UNIQUE(user,bathroom,at), UNIQUE(id,bathroom,user));
CREATE TABLE reviews (id TEXT PRIMARY KEY NOT NULL CHECK(length(id)>0), visit TEXT NOT NULL UNIQUE, bathroom TEXT NOT NULL, author TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL CHECK(updated>=created), rating REAL NOT NULL CHECK(rating>=0 AND rating<=5), paper INTEGER NOT NULL CHECK(paper BETWEEN 0 AND 2), hygiene INTEGER NOT NULL CHECK(hygiene BETWEEN 0 AND 4), comfort INTEGER NOT NULL CHECK(comfort BETWEEN 0 AND 4), aesthetics INTEGER NOT NULL CHECK(aesthetics BETWEEN 0 AND 4), tags TEXT NOT NULL, FOREIGN KEY(visit,bathroom,author) REFERENCES visits(id,bathroom,user));
CREATE TABLE favourites (user TEXT NOT NULL CHECK(length(user)>0), bathroom TEXT NOT NULL REFERENCES bathrooms(id), PRIMARY KEY(user,bathroom));
''';

  T transaction<T>(T Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  LocalData? load() {
    if (database.select('SELECT * FROM metadata').isEmpty) {
      if (database.select('SELECT id FROM bathrooms').isNotEmpty ||
          database.select('SELECT id FROM visits').isNotEmpty ||
          database.select('SELECT id FROM reviews').isNotEmpty ||
          database.select('SELECT user FROM favourites').isNotEmpty) {
        throw StateError('Missing initialization marker');
      }
      return null;
    }
    DateTime date(Object? value) =>
        DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true);
    return LocalData(
      bathrooms: [
        for (final r in database.select(
          'SELECT * FROM bathrooms ORDER BY rowid',
        ))
          Bathroom(
            id: r['id'] as String,
            name: r['name'] as String,
            createdBy: r['creator'] as String,
            emoji: r['emoji'] as String,
            accent: r['accent'] as int,
          ),
      ],
      visits: [
        for (final r in database.select('SELECT * FROM visits ORDER BY rowid'))
          Visit(
            id: r['id'] as String,
            bathroomId: r['bathroom'] as String,
            userId: r['user'] as String,
            visitedAt: date(r['at']),
          ),
      ],
      reviews: [
        for (final r in database.select('SELECT * FROM reviews ORDER BY rowid'))
          Review(
            id: r['id'] as String,
            visitId: r['visit'] as String,
            bathroomId: r['bathroom'] as String,
            authorId: r['author'] as String,
            createdAt: date(r['created']),
            updatedAt: date(r['updated']),
            rating: (r['rating'] as num).toDouble(),
            paperAvailability: r['paper'] as int,
            hygiene: r['hygiene'] as int,
            comfort: r['comfort'] as int,
            aesthetics: r['aesthetics'] as int,
            tags: (jsonDecode(r['tags'] as String) as List).cast<String>(),
          ),
      ],
      favourites: [
        for (final r in database.select('SELECT * FROM favourites'))
          BathroomActivity(
            userId: r['user'] as String,
            bathroomId: r['bathroom'] as String,
            isFavorite: true,
          ),
      ],
      darkMode:
          database
              .select('SELECT dark_mode FROM settings WHERE id=1')
              .single['dark_mode'] ==
          1,
    );
  }

  /// Bounded local prototype: replace a consistent snapshot in one transaction.
  void save(LocalData data) => transaction(() {
    for (final table in ['reviews', 'visits', 'favourites', 'bathrooms']) {
      database.execute('DELETE FROM $table');
    }
    for (final b in data.bathrooms) {
      database.execute('INSERT INTO bathrooms VALUES(?,?,?,?,?,?)', [
        b.id,
        b.name,
        b.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
        b.createdBy,
        b.emoji,
        b.accent,
      ]);
    }
    for (final v in data.visits) {
      database.execute('INSERT INTO visits VALUES(?,?,?,?)', [
        v.id,
        v.bathroomId,
        v.userId,
        v.visitedAt.microsecondsSinceEpoch,
      ]);
    }
    for (final r in data.reviews) {
      database.execute('INSERT INTO reviews VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
        r.id,
        r.visitId,
        r.bathroomId,
        r.authorId,
        r.createdAt.microsecondsSinceEpoch,
        r.updatedAt.microsecondsSinceEpoch,
        r.rating,
        r.paperAvailability,
        r.hygiene,
        r.comfort,
        r.aesthetics,
        jsonEncode(r.tags),
      ]);
    }
    for (final f in data.favourites.where((f) => f.isFavorite)) {
      database.execute('INSERT INTO favourites VALUES(?,?)', [
        f.userId,
        f.bathroomId,
      ]);
    }
    database.execute('UPDATE settings SET dark_mode=? WHERE id=1', [
      data.darkMode ? 1 : 0,
    ]);
    database.execute('INSERT OR IGNORE INTO metadata VALUES(1,1)');
  });
  void close() => database.close();
}
