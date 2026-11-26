import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/provenance.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/local_store.dart';

Review review(Visit v) => Review(
  id: 'review-${v.id}',
  visitId: v.id,
  bathroomId: v.bathroomId,
  authorId: v.userId,
  createdAt: v.visitedAt,
  rating: 0,
  paperAvailability: 0,
  hygiene: 1,
  comfort: 2,
  aesthetics: 3,
  tags: ['👩🏽‍💻 Tecnologia'],
  comment: 'Comentário histórico',
);

void main() {
  late LocalStore store;
  late AppState app;
  setUp(() {
    store = LocalStore(sqlite3.openInMemory());
    app = AppState.restore(store);
  });
  tearDown(() {
    app.dispose();
    store.close();
  });

  test('first run is idempotent and reads/notifications cause zero writes', () {
    final db = store.database;
    final changes = db.select('SELECT total_changes() AS n').single['n'];
    final restored = AppState.restore(store);
    restored.dispose();
    store.initialize(app.localData);
    app.notifyListeners();
    app.retryStorage();
    app.entries;
    app.visitsFor('0');
    app.activityFor('0');
    store.load();
    expect(db.select('SELECT total_changes() AS n').single['n'], changes);
    expect(app.visits.length, 6);
  });

  test('targeted actions leave unrelated rows untouched', () {
    final db = store.database;
    db.execute('CREATE TABLE audit_log (entity TEXT, action TEXT)');
    for (final table in [
      'bathrooms',
      'visits',
      'reviews',
      'favourites',
      'settings',
    ]) {
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        db.execute(
          "CREATE TRIGGER audit_${table}_$action AFTER $action ON $table BEGIN INSERT INTO audit_log VALUES('$table','$action'); END",
        );
      }
    }
    void expectWrites(List<String> expected) {
      expect(
        db
            .select('SELECT * FROM audit_log')
            .map((r) => '${r['entity']}:${r['action']}'),
        expected,
      );
      db.execute('DELETE FROM audit_log');
    }

    final b = app.createBathroom('Novo');
    expectWrites(['bathrooms:INSERT']);
    app.updateBathroom(
      Bathroom(
        id: b.id,
        name: 'Novo nome',
        createdBy: b.createdBy,
        emoji: '👑',
        accent: 4,
      ),
    );
    expectWrites(['bathrooms:UPDATE']);
    final v = app.recordVisit(b.id, visitedAt: DateTime.utc(2030));
    expectWrites(['visits:INSERT']);
    app.saveReview(review(v));
    expectWrites(['reviews:INSERT']);
    app.saveReview(review(v));
    expectWrites(['reviews:UPDATE']);
    app.toggleFavorite(b.id);
    expectWrites(['favourites:INSERT']);
    app.toggleFavorite(b.id);
    expectWrites(['favourites:DELETE']);
    app.toggleTheme();
    expectWrites(['settings:UPDATE']);
    app.deleteVisit(v.id, deleteReview: true);
    expectWrites(['reviews:DELETE', 'visits:DELETE']);
    final undo = app.recordVisit(b.id, visitedAt: DateTime.utc(2031));
    expectWrites(['visits:INSERT']);
    expect(app.undoVisit(undo.id), true);
    expectWrites(['visits:DELETE']);
  });

  test('atomic direct review rolls back and retries exact IDs once', () {
    final db = store.database;
    db.execute(
      "CREATE TRIGGER fail_review BEFORE INSERT ON reviews BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    final v = Visit(
      id: 'pending',
      bathroomId: '0',
      userId: app.currentUserId,
      visitedAt: DateTime.utc(2030),
    );
    var successes = 0;
    app.addListener(() {
      if (app.storageError == null) {
        successes++;
        expect(store.load()!.reviews.any((r) => r.visitId == v.id), true);
      }
    });
    app.saveReview(review(v), newVisit: v);
    expect(app.storageError, isNotNull);
    expect(app.visits.any((r) => r.id == v.id), false);
    expect(store.load()!.visits.any((r) => r.id == v.id), false);
    expect(() => app.toggleTheme(), throwsStateError);
    app.notifyListeners();
    app.retryStorage();
    expect(successes, 0);
    db.execute('DROP TRIGGER fail_review');
    app.retryStorage();
    app.retryStorage();
    expect(successes, 1);
    expect(app.visits.where((r) => r.id == v.id).length, 1);
    expect(store.load()!.reviews.where((r) => r.visitId == v.id).length, 1);
  });

  test(
    'failed action completion waits for retry and legacy children stay excluded',
    () async {
      final b = app.createBathroom('Legado');
      store.database.execute(
        "UPDATE bathrooms SET provenance='unclassified_legacy' WHERE id=?",
        [b.id],
      );
      store.database.execute('PRAGMA query_only=ON');
      final v = app.recordVisit(b.id, visitedAt: DateTime.utc(2030));
      var completed = false;
      final completion = app.persistenceComplete.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      expect(app.visits.any((r) => r.id == v.id), false);
      store.database.execute('PRAGMA query_only=OFF');
      app.retryStorage();
      await completion;
      app.saveReview(review(v));
      app.toggleFavorite(b.id);
      for (final table in ['visits', 'reviews', 'favourites']) {
        final origin = Provenance.fromValue(
          store.database.select(
                'SELECT provenance FROM $table WHERE bathroom=?',
                [b.id],
              ).single['provenance']
              as String,
        );
        expect(origin, Provenance.unclassifiedLegacy);
        expect(origin.allowsFutureUpload, false);
      }
    },
  );

  test('fixture failure rolls back marker and all records before retry', () {
    final fresh = LocalStore(sqlite3.openInMemory());
    addTearDown(fresh.close);
    fresh.database.execute(
      "CREATE TRIGGER fail_seed BEFORE INSERT ON reviews BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    expect(() => AppState.restore(fresh), throwsA(isA<SqliteException>()));
    expect(fresh.load(), isNull);
    expect(fresh.database.select('SELECT * FROM bathrooms'), isEmpty);
    fresh.database.execute('DROP TRIGGER fail_seed');
    final seeded = AppState.restore(fresh);
    expect(seeded.allBathrooms.length, 6);
    seeded.dispose();
    final restored = AppState.restore(fresh);
    expect(restored.visits.length, 6);
    restored.dispose();
  });

  test('delete rollback retains review and visit until successful retry', () {
    final db = store.database;
    db.execute(
      "CREATE TRIGGER fail_delete BEFORE DELETE ON visits BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    app.deleteVisit('visit-0', deleteReview: true);
    expect(app.storageError, isNotNull);
    expect(app.reviewForVisit('visit-0'), isNotNull);
    expect(store.load()!.reviews.any((r) => r.visitId == 'visit-0'), true);
    db.execute('DROP TRIGGER fail_delete');
    app.retryStorage();
    expect(app.reviewForVisit('visit-0'), isNull);
    expect(store.load()!.visits.any((r) => r.id == 'visit-0'), false);
  });

  test(
    'new records inherit demo and genuine provenance, edits retain origin',
    () {
      final b = app.createBathroom('Genuíno');
      for (final id in ['0', b.id]) {
        final v = app.recordVisit(id, visitedAt: DateTime.utc(2030));
        app.saveReview(review(v));
        app.toggleFavorite(id);
        final expected = id == '0' ? 'demo' : 'user_created';
        expect(store.bathroomProvenance(id).value, expected);
        for (final table in ['visits', 'reviews', 'favourites']) {
          expect(
            store.database
                .select('SELECT provenance FROM $table WHERE bathroom=?', [id])
                .every((r) => r['provenance'] == expected),
            true,
          );
        }
      }
      final seed = app.allBathrooms.first;
      app.updateBathroom(
        Bathroom(
          id: seed.id,
          name: 'Amostra alterada',
          createdBy: seed.createdBy,
        ),
      );
      expect(store.bathroomProvenance(seed.id), Provenance.demo);
      expect(Provenance.demo.allowsFutureUpload, false);
      expect(Provenance.unclassifiedLegacy.allowsFutureUpload, false);
      expect(Provenance.remote.allowsFutureUpload, false);
      expect(Provenance.userCreated.allowsFutureUpload, true);
    },
  );

  test(
    'distributed v4 upgrade preserves exact content and classifies conservatively',
    () {
      final dir = Directory.systemTemp.createTempSync('v4-upgrade');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/historical.sqlite';
      final db = sqlite3.open(path);
      db.execute(LocalStore.schemaV1);
      db.execute(
        'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), dark_mode INTEGER NOT NULL CHECK(dark_mode IN (0,1)))',
      );
      db.execute('INSERT INTO settings VALUES(1,0)');
      db.execute(
        "ALTER TABLE bathrooms ADD COLUMN emoji TEXT NOT NULL DEFAULT '🚽' CHECK(length(emoji)>0)",
      );
      db.execute(
        'ALTER TABLE bathrooms ADD COLUMN accent INTEGER NOT NULL DEFAULT 0 CHECK(accent BETWEEN 0 AND 5)',
      );
      db.execute('ALTER TABLE reviews ADD COLUMN comment TEXT');
      db.execute('INSERT INTO metadata VALUES(1,1)');
      for (final id in ['0', 'legacy-uuid']) {
        db.execute('INSERT INTO bathrooms VALUES(?,?,?,?,?,?)', [
          id,
          'Edited $id',
          'edited $id',
          'local-user',
          '👑',
          5,
        ]);
        db.execute('INSERT INTO visits VALUES(?,?,?,?)', [
          'v-$id',
          id,
          'local-user',
          123456789,
        ]);
        db.execute('INSERT INTO reviews VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)', [
          'r-$id',
          'v-$id',
          id,
          'local-user',
          123456790,
          123456791,
          0.0,
          2,
          4,
          3,
          1,
          '[{"emoji":"👩🏽‍💻","label":"Tecnologia"}]',
          'Texto\noriginal',
        ]);
        db.execute('INSERT INTO favourites VALUES(?,?)', ['local-user', id]);
      }
      db.userVersion = 4;
      final before = <String, List<List<Object?>>>{};
      for (final table in [
        'bathrooms',
        'visits',
        'reviews',
        'favourites',
        'settings',
        'metadata',
      ]) {
        before[table] = db
            .select('SELECT * FROM $table')
            .map((r) => r.values.toList())
            .toList();
      }
      db.close();
      final upgraded = LocalStore(sqlite3.open(path));
      for (final table in before.keys) {
        final rows = upgraded.database.select('SELECT * FROM $table');
        expect(
          rows.map((r) => r.values.take(before[table]!.first.length).toList()),
          before[table],
        );
      }
      expect(upgraded.bathroomProvenance('0'), Provenance.demo);
      expect(
        upgraded.bathroomProvenance('legacy-uuid'),
        Provenance.unclassifiedLegacy,
      );
      for (final table in ['visits', 'reviews', 'favourites']) {
        expect(
          upgraded.database
              .select('SELECT provenance FROM $table ORDER BY rowid')
              .map((r) => r['provenance']),
          ['demo', 'unclassified_legacy'],
        );
      }
      upgraded.close();
      final reopened = LocalStore(sqlite3.open(path));
      expect(reopened.load()!.reviews.length, 2);
      expect(reopened.load()!.darkMode, false);
      reopened.close();
    },
  );

  test(
    'migration failure rolls back DDL and version and preserves original database',
    () {
      final dir = Directory.systemTemp.createTempSync('migration-rollback');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/bad.sqlite';
      final db = sqlite3.open(path);
      db.execute(LocalStore.schemaV1);
      db.execute(
        "INSERT INTO bathrooms VALUES('b','Original','original','me')",
      );
      db.execute("INSERT INTO visits VALUES('v','missing','me',123)");
      db.userVersion = 1;
      db.close();
      expect(() => LocalStore(sqlite3.open(path)), throwsStateError);
      final check = sqlite3.open(path);
      expect(check.userVersion, 1);
      expect(
        check.select('SELECT name FROM bathrooms').single['name'],
        'Original',
      );
      expect(
        check.select("SELECT name FROM sqlite_master WHERE name='settings'"),
        isEmpty,
      );
      expect(
        check
            .select('PRAGMA table_info(bathrooms)')
            .any((r) => r['name'] == 'provenance'),
        false,
      );
      check.close();
    },
  );
}
