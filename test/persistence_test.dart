import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';

void main() {
  test(
    'restart restores entities, optional visits, theme, favourites and deletions',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'bath-storage-test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/test.sqlite';
      var store = LocalStore(sqlite3.open(path));
      var app = AppState.restore(store);
      expect(app.visits.length, 6);
      final bathroom = app.createBathroom(
        'Trono persistente',
        emoji: '👑',
        accent: 4,
      );
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(bathroom.id), isTrue);
      final visit = app.recordVisit(bathroom.id, visitedAt: DateTime.utc(2030));
      app.toggleFavorite(bathroom.id);
      app.toggleTheme();
      app.deleteVisit('visit-0', deleteReview: true);
      app.dispose();
      store.close();
      store = LocalStore(sqlite3.open(path));
      app = AppState.restore(store);
      expect(app.allBathrooms.length, 7);
      final identity = app.allBathrooms.firstWhere((b) => b.id == bathroom.id);
      expect(identity.emoji, '👑');
      expect(identity.accent, 4);
      expect(app.visits.any((v) => v.id == visit.id), isTrue);
      expect(app.reviews.length, 4);
      expect(app.visits.any((v) => v.id == 'visit-0'), isFalse);
      expect(app.activityFor(bathroom.id).isFavorite, isTrue);
      expect(app.darkMode, isFalse);
      app.dispose();
      store.close();
    },
  );

  test(
    'atomic review creation survives reopen and empty initialized data is not reseeded',
    () {
      final dir = Directory.systemTemp.createTempSync('bath-atomic-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/data.sqlite';
      var store = LocalStore(sqlite3.open(path));
      var app = AppState.restore(store);
      final visit = Visit(
        id: AppState.newEntityId(),
        bathroomId: '0',
        userId: app.currentUserId,
        visitedAt: DateTime.utc(2030),
      );
      final r = Review(
        id: AppState.newEntityId(),
        visitId: visit.id,
        bathroomId: '0',
        authorId: app.currentUserId,
        createdAt: DateTime.utc(2030),
        rating: 0,
        paperAvailability: 0,
        hygiene: 0,
        comfort: 0,
        aesthetics: 0,
        tags: ['teste'],
      );
      app.saveReview(r, newVisit: visit);
      app.dispose();
      store.close();
      store = LocalStore(sqlite3.open(path));
      app = AppState.restore(store);
      expect(app.reviewForVisit(visit.id)!.tags, ['teste']);
      expect(app.reviewForVisit(visit.id)!.rating, 0);
      expect(app.visits.length, 7);
      store.save(
        LocalData(
          bathrooms: [],
          visits: [],
          reviews: [],
          favourites: [],
          darkMode: false,
        ),
      );
      app.dispose();
      store.close();
      store = LocalStore(sqlite3.open(path));
      app = AppState.restore(store);
      expect(app.allBathrooms, isEmpty);
      expect(app.visits, isEmpty);
      app.dispose();
      store.close();
    },
  );

  test('schema v1 migrates to v3 without losing records', () {
    final db = sqlite3.openInMemory();
    db.execute(LocalStore.schemaV1);
    db.execute("INSERT INTO bathrooms VALUES('b','Trono','trono','me')");
    db.execute('INSERT INTO metadata VALUES(1,1)');
    db.userVersion = 1;
    final store = LocalStore(db);
    addTearDown(store.close);
    expect(db.userVersion, 3);
    expect(store.load()!.bathrooms.single.id, 'b');
    expect(store.load()!.darkMode, isTrue);
  });

  test('failed snapshot transaction retains original records', () {
    final store = LocalStore(sqlite3.openInMemory());
    addTearDown(store.close);
    final app = AppState.restore(store);
    addTearDown(app.dispose);
    final original = app.localData;
    expect(
      () => store.save(
        LocalData(
          bathrooms: [],
          visits: original.visits,
          reviews: original.reviews,
          favourites: [],
          darkMode: false,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(store.load()!.bathrooms.length, 6);
    expect(store.load()!.reviews.length, 5);
    expect(store.load()!.darkMode, isTrue);
    expect(
      () => store.database.execute(
        "INSERT INTO reviews SELECT 'duplicate',visit,bathroom,author,created,updated,rating,paper,hygiene,comfort,aesthetics,tags FROM reviews LIMIT 1",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => store.database.execute("UPDATE reviews SET author='someone-else'"),
      throwsA(isA<SqliteException>()),
    );
  });

  test('write failure is visible, retry preserves in-memory changes', () {
    final store = LocalStore(sqlite3.openInMemory());
    addTearDown(store.close);
    final app = AppState.restore(store);
    addTearDown(app.dispose);
    store.database.execute('PRAGMA query_only=ON');
    final b = app.createBathroom('Guardado depois');
    expect(app.storageError, isNotNull);
    expect(store.load()!.bathrooms.length, 6);
    store.database.execute('PRAGMA query_only=OFF');
    app.retryStorage();
    expect(app.storageError, isNull);
    expect(store.load()!.bathrooms.any((r) => r.id == b.id), isTrue);
  });

  test('corrupt and future databases are preserved and refused', () {
    final dir = Directory.systemTemp.createTempSync('bath-corrupt-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/corrupt.sqlite')
      ..writeAsStringSync('original invalid data');
    expect(() => LocalStore(sqlite3.open(file.path)), throwsA(anything));
    expect(file.readAsStringSync(), 'original invalid data');
    final future = '${dir.path}/future.sqlite';
    final db = sqlite3.open(future)..userVersion = 99;
    db.close();
    expect(() => LocalStore(sqlite3.open(future)), throwsStateError);
    final check = sqlite3.open(future);
    expect(check.userVersion, 99);
    check.close();
  });

  test(
    'visit chronology beats delayed review submission and rapid taps reuse visit',
    () {
      final app = AppState(bathrooms: []);
      addTearDown(app.dispose);
      final b = app.createBathroom('Cronologia');
      final old = app.recordVisit(b.id, visitedAt: DateTime.utc(2020));
      final latest = app.recordVisit(b.id, visitedAt: DateTime.utc(2021));
      expect(
        app
            .recordVisit(
              b.id,
              visitedAt: DateTime.utc(
                2021,
              ).add(const Duration(milliseconds: 50)),
            )
            .id,
        latest.id,
      );
      Review make(String id, String visit, int year, double rating) => Review(
        id: id,
        visitId: visit,
        bathroomId: b.id,
        authorId: app.currentUserId,
        createdAt: DateTime.utc(year),
        rating: rating,
        paperAvailability: 2,
        hygiene: 4,
        comfort: 4,
        aesthetics: 4,
      );
      app.saveReview(make('recent', latest.id, 2022, 4));
      app.saveReview(make('delayed', old.id, 2023, 1));
      expect(app.entries.single.personalReview!.id, 'recent');
      expect(app.visits.length, 2);
    },
  );
}
