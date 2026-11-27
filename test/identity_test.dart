import 'dart:convert';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'v9 additive migration preserves legacy colours, historical scores and queued payloads',
    () {
      final db = sqlite3.openInMemory();
      var store = LocalStore(db);
      final state = AppState.restore(store);
      final old = state.allBathrooms.first;
      final original = state.reviews.first.rating;
      final rows = jsonEncode(
        db.select('SELECT * FROM reviews').map((r) => Map.of(r)).toList(),
      );
      db.execute('ALTER TABLE bathrooms DROP COLUMN accent_rgb');
      db.userVersion = 9;
      // Same connection, reopen logically without disposing the owned database.
      store = LocalStore(db);
      final data = store.load()!;
      expect(data.bathrooms.first.accent, old.accent);
      expect(data.bathrooms.first.accentRgb, isNull);
      expect(data.bathrooms.first.emoji, old.emoji);
      expect(data.reviews.first.rating, original);
      expect(
        jsonEncode(
          db.select('SELECT * FROM reviews').map((r) => Map.of(r)).toList(),
        ),
        rows,
      );
      final changed = state.createBathroom(
        'RGB',
        emoji: '🏳️‍🌈',
        accentRgb: 0x010203,
      );
      expect(
        store
            .load()!
            .bathrooms
            .singleWhere((b) => b.id == changed.id)
            .accentRgb,
        0x010203,
      );
      state.dispose();
      store.close();
    },
  );

  test('v3 upgrades tags and comments once without resetting records', () {
    final db = sqlite3.openInMemory();
    db.execute(LocalStore.schemaV1);
    db.execute(
      'CREATE TABLE settings (id INTEGER PRIMARY KEY, dark_mode INTEGER NOT NULL)',
    );
    db.execute('INSERT INTO settings VALUES(1,0)');
    db.execute(
      "ALTER TABLE bathrooms ADD COLUMN emoji TEXT NOT NULL DEFAULT '🚽'",
    );
    db.execute(
      'ALTER TABLE bathrooms ADD COLUMN accent INTEGER NOT NULL DEFAULT 0',
    );
    db.execute('INSERT INTO metadata VALUES(1,1)');
    db.execute("INSERT INTO bathrooms VALUES('b','Teste','teste','me','👑',4)");
    db.execute("INSERT INTO visits VALUES('v','b','me',123)");
    db.execute('INSERT INTO reviews VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
      'r',
      'v',
      'b',
      'me',
      123,
      123,
      0,
      0,
      0,
      0,
      0,
      '["👩🏽‍💻 Tecnologia","Nice"]',
    ]);
    db.userVersion = 3;
    final store = LocalStore(db);
    addTearDown(store.close);
    final data = store.load()!;
    expect(db.userVersion, 10);
    expect(data.reviews.single.tags.first.emoji, '👩🏽‍💻');
    expect(data.reviews.single.tags.first.label, 'Tecnologia');
    expect(data.reviews.single.comment, isNull);
    expect(data.bathrooms.single.emoji, '👑');
    expect(data.darkMode, false);
    store.initialize(data);
    expect(store.load()!.reviews.single.tags, data.reviews.single.tags);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
  });
  test('v2 migration preserves every entity, tag, favourite and setting', () {
    final db = sqlite3.openInMemory();
    db.execute(LocalStore.schemaV1);
    db.execute(
      'CREATE TABLE settings (id INTEGER PRIMARY KEY, dark_mode INTEGER NOT NULL)',
    );
    db.execute('INSERT INTO settings VALUES(1,0)');
    db.execute('INSERT INTO metadata VALUES(1,1)');
    db.execute(
      "INSERT INTO bathrooms VALUES('3','Biblioteca','biblioteca','original')",
    );
    db.execute(
      "INSERT INTO bathrooms VALUES('other','Outro','outro','original')",
    );
    db.execute("INSERT INTO visits VALUES('v','3','me',123)");
    db.execute("INSERT INTO visits VALUES('unreviewed','other','me',124)");
    db.execute('INSERT INTO reviews VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
      'r',
      'v',
      '3',
      'me',
      123,
      123,
      0,
      0,
      0,
      0,
      0,
      '["cozy","🎨 grafiti","unknown"]',
    ]);
    db.execute("INSERT INTO favourites VALUES('me','3')");
    db.userVersion = 2;
    final store = LocalStore(db);
    addTearDown(store.close);
    final data = store.load()!;
    expect(db.userVersion, 10);
    expect(data.bathrooms.first.emoji, '📚');
    expect(data.bathrooms.first.createdBy, 'original');
    expect(data.visits.map((v) => v.id), ['v', 'unreviewed']);
    expect(data.reviews.single.rating, 0);
    expect(data.reviews.single.comment, isNull);
    expect(data.reviews.single.tags.map((t) => t.emoji), ['🛋️', '🎨', '🏷️']);
    expect(data.reviews.single.tags.map((t) => t.label), [
      'cozy',
      'grafiti',
      'unknown',
    ]);
    expect(data.favourites.single.bathroomId, '3');
    expect(data.darkMode, false);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    final other = data.bathrooms.last;
    expect(
      other.emoji,
      const Bathroom(id: 'other', name: 'Outro', createdBy: 'original').emoji,
    );
    store.initialize(data);
    expect(store.load()!.bathrooms.last.emoji, other.emoji);
    expect(store.load()!.bathrooms.last.accent, other.accent);
  });
  test('selected identities restore and invalid options are rejected', () {
    final store = LocalStore(sqlite3.openInMemory());
    addTearDown(store.close);
    final state = AppState.restore(store);
    addTearDown(state.dispose);
    expect(state.visits.any((v) => state.reviewForVisit(v.id) == null), isTrue);
    expect(state.entries.any((e) => e.activity.visitCount == 0), isTrue);
    expect(state.localData.favourites, isNotEmpty);
    final b = state.createBathroom('Trono real', emoji: '👑', accent: 4);
    final restored = AppState.restore(store);
    addTearDown(restored.dispose);
    final copy = restored.allBathrooms.firstWhere((item) => item.id == b.id);
    expect(copy.emoji, '👑');
    expect(copy.accent, 4);
    expect(
      () => state.createBathroom('Inválido', accent: 6),
      throwsArgumentError,
    );
    expect(
      () => state.createBathroom('Inválido', emoji: 'oops'),
      throwsArgumentError,
    );
  });
}
