import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../models/bathroom.dart';
import '../models/bathroom_activity.dart';
import '../models/review.dart';
import '../models/tag_presentation.dart';
import '../models/visit.dart';
import '../models/provenance.dart';
import '../sync/namespace.dart';

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
  final DataNamespace namespace;
  LocalStore(this.database, {DataNamespace? namespace})
    : namespace = namespace ?? const DataNamespace.guest() {
    try {
      database.execute('PRAGMA foreign_keys = ON');
      if (database.select('PRAGMA quick_check').single.values.single != 'ok') {
        throw StateError('Database integrity check failed');
      }
      final version = database.userVersion;
      if (version > 8) {
        throw StateError('Database was created by a newer application');
      }
      // SQLite's documented table-rebuild procedure keeps child references intact.
      if (version < 7 && this.namespace.isAccount) {
        database.execute('PRAGMA foreign_keys = OFF');
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
        if (version < 4) {
          database.execute('ALTER TABLE reviews ADD COLUMN comment TEXT');
          for (final row in database.select('SELECT id,tags FROM reviews')) {
            final tags = (jsonDecode(row['tags'] as String) as List)
                .map((t) => ReviewTagData.legacy(t as String))
                .toList();
            database.execute('UPDATE reviews SET tags=? WHERE id=?', [
              jsonEncode(tags),
              row['id'],
            ]);
          }
          database.userVersion = 4;
        }
        if (version < 5) {
          for (final table in [
            'bathrooms',
            'visits',
            'reviews',
            'favourites',
          ]) {
            database.execute(
              "ALTER TABLE $table ADD COLUMN provenance TEXT NOT NULL DEFAULT 'unclassified_legacy' CHECK(provenance IN ('demo','unclassified_legacy','user_created','remote'))",
            );
          }
          // Stable seed identities remain fictional even after local edits.
          database.execute(
            "UPDATE bathrooms SET provenance='demo' WHERE id IN ('0','1','2','3','4','5')",
          );
          for (final table in ['visits', 'reviews', 'favourites']) {
            database.execute(
              "UPDATE $table SET provenance='demo' WHERE bathroom IN (SELECT id FROM bathrooms WHERE provenance='demo')",
            );
          }
          database.userVersion = 5;
        }
        if (version < 6) {
          if (version != 0 && this.namespace.kind != 'guest') {
            throw StateError('Existing data belongs to the local guest');
          }
          database.execute(syncSchemaV6);
          database.execute('INSERT INTO namespace VALUES(1,?)', [
            this.namespace.key,
          ]);
          if (version == 0 && this.namespace.kind != 'guest') {
            // Account/public stores start empty; only guest bootstrap seeds fiction.
            database.execute('INSERT INTO metadata VALUES(1,1)');
          }
          database.userVersion = 6;
        }
        if (version < 7) {
          if (this.namespace.isAccount) {
            database.execute('''CREATE TABLE bathrooms_v7 (
              id TEXT PRIMARY KEY NOT NULL CHECK(length(id)>0), name TEXT NOT NULL,
              normalized_name TEXT NOT NULL, creator TEXT NOT NULL CHECK(length(creator)>0),
              emoji TEXT NOT NULL CHECK(length(emoji)>0), accent INTEGER NOT NULL CHECK(accent BETWEEN 0 AND 5),
              provenance TEXT NOT NULL CHECK(provenance IN ('demo','unclassified_legacy','user_created','remote')));
              INSERT INTO bathrooms_v7 SELECT * FROM bathrooms;
              DROP TABLE bathrooms;
              ALTER TABLE bathrooms_v7 RENAME TO bathrooms;
            ''');
          }
          database.execute('''CREATE TABLE sync_preferences (
            id INTEGER PRIMARY KEY CHECK(id=1), consent_version INTEGER NOT NULL);
            CREATE TABLE sync_resolutions (operation_id TEXT PRIMARY KEY REFERENCES outbox(operation_id), resolution TEXT NOT NULL);
          ''');
          database.userVersion = 7;
        }
        if (version < 8) {
          database.execute('''
            CREATE TABLE catalogue_bathrooms (id TEXT PRIMARY KEY REFERENCES bathrooms(id));
            CREATE TABLE bathroom_links (private_id TEXT PRIMARY KEY REFERENCES bathrooms(id), shared_id TEXT NOT NULL REFERENCES bathrooms(id));
          ''');
          database.userVersion = 8;
        }
        if (database.select('SELECT scope FROM namespace').single['scope'] !=
            this.namespace.key) {
          throw StateError('Database namespace mismatch');
        }
        if (database.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw StateError('Broken database references');
        }
      });
      database.execute('PRAGMA foreign_keys = ON');
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
            tags: (jsonDecode(r['tags'] as String) as List).map(
              (t) => ReviewTagData.fromJson(t as Map<String, dynamic>),
            ),
            comment: r['comment'] as String?,
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

  /// Only first-run fixtures use this bulk path; the marker commits with them.
  void initialize(LocalData data) => transaction(() {
    if (load() != null) return;
    for (final b in data.bathrooms) {
      insertBathroom(b, provenance: Provenance.demo);
    }
    for (final v in data.visits) {
      insertVisit(v);
    }
    for (final r in data.reviews) {
      writeReview(r, isNew: true);
    }
    for (final f in data.favourites.where((f) => f.isFavorite)) {
      setFavourite(f.userId, f.bathroomId, true);
    }
    setDarkMode(data.darkMode);
    database.execute('INSERT INTO metadata VALUES(1,1)');
  });

  void insertBathroom(Bathroom b, {required Provenance provenance}) {
    database.execute('INSERT INTO bathrooms VALUES(?,?,?,?,?,?,?)', [
      b.id,
      b.name,
      b.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      b.createdBy,
      b.emoji,
      b.accent,
      provenance.value,
    ]);
  }

  void updateBathroom(Bathroom b) {
    database.execute(
      'UPDATE bathrooms SET name=?,normalized_name=?,emoji=?,accent=? WHERE id=? AND creator=?',
      [
        b.name,
        b.name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
        b.emoji,
        b.accent,
        b.id,
        b.createdBy,
      ],
    );
    if (database.updatedRows != 1) {
      throw StateError('Bathroom identity changed');
    }
  }

  Provenance bathroomProvenance(String id) => Provenance.fromValue(
    database.select('SELECT provenance FROM bathrooms WHERE id=?', [
          id,
        ]).single['provenance']
        as String,
  );

  void insertVisit(Visit v) {
    database.execute('INSERT INTO visits VALUES(?,?,?,?,?)', [
      v.id,
      v.bathroomId,
      v.userId,
      v.visitedAt.microsecondsSinceEpoch,
      bathroomProvenance(v.bathroomId).child.value,
    ]);
  }

  void writeReview(Review r, {required bool isNew}) {
    final content = [
      r.updatedAt.microsecondsSinceEpoch,
      r.rating,
      r.paperAvailability,
      r.hygiene,
      r.comfort,
      r.aesthetics,
      jsonEncode(r.tags),
      r.comment,
    ];
    if (isNew) {
      final origin = Provenance.fromValue(
        database.select('SELECT provenance FROM visits WHERE id=?', [
              r.visitId,
            ]).single['provenance']
            as String,
      );
      database.execute(
        'INSERT INTO reviews (id,visit,bathroom,author,created,updated,rating,paper,hygiene,comfort,aesthetics,tags,comment,provenance) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          r.id,
          r.visitId,
          r.bathroomId,
          r.authorId,
          r.createdAt.microsecondsSinceEpoch,
          ...content,
          origin.child.value,
        ],
      );
    } else {
      database.execute(
        'UPDATE reviews SET updated=?,rating=?,paper=?,hygiene=?,comfort=?,aesthetics=?,tags=?,comment=? WHERE id=? AND visit=? AND bathroom=? AND author=? AND created=? AND updated<=?',
        [
          ...content,
          r.id,
          r.visitId,
          r.bathroomId,
          r.authorId,
          r.createdAt.microsecondsSinceEpoch,
          r.updatedAt.microsecondsSinceEpoch,
        ],
      );
      if (database.updatedRows != 1) {
        throw StateError('Review identity changed');
      }
    }
  }

  void removeVisit(String id) {
    database.execute('DELETE FROM reviews WHERE visit=?', [id]);
    database.execute('DELETE FROM visits WHERE id=?', [id]);
  }

  void setFavourite(String user, String bathroom, bool value) {
    if (value) {
      database.execute(
        'INSERT INTO favourites VALUES(?,?,?) ON CONFLICT(user,bathroom) DO NOTHING',
        [user, bathroom, bathroomProvenance(bathroom).child.value],
      );
    } else {
      database.execute('DELETE FROM favourites WHERE user=? AND bathroom=?', [
        user,
        bathroom,
      ]);
    }
  }

  void setDarkMode(bool value) => database.execute(
    'UPDATE settings SET dark_mode=? WHERE id=1',
    [value ? 1 : 0],
  );
  bool _closed = false;
  bool get isClosed => _closed;
  void close() {
    if (_closed) return;
    database.close();
    _closed = true;
  }
}
