import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
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
    expect(db.userVersion, 3);
    expect(data.bathrooms.first.emoji, '📚');
    expect(data.bathrooms.first.createdBy, 'original');
    expect(data.visits.map((v) => v.id), ['v', 'unreviewed']);
    expect(data.reviews.single.rating, 0);
    expect(data.reviews.single.tags, ['cozy', '🎨 grafiti', 'unknown']);
    expect(data.favourites.single.bathroomId, '3');
    expect(data.darkMode, false);
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    final other = data.bathrooms.last;
    expect(
      other.emoji,
      const Bathroom(id: 'other', name: 'Outro', createdBy: 'original').emoji,
    );
    store.save(data);
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
