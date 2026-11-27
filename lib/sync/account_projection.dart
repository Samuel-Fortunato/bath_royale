import 'dart:convert';
import '../models/provenance.dart';
import '../models/bathroom.dart';
import '../storage/local_store.dart';
import 'sync_store.dart';

/// Projects canonical account rows without overwriting any unresolved local edit.
/// The cache remains separate and replayable. Projection never creates an outbox.
class AccountProjection {
  final SyncStore sync;
  AccountProjection(this.sync);
  LocalStore get local => sync.local;

  void apply() => local.transaction(() {
    final db = local.database;
    final dirty = <(String, String)>{};
    for (final row in db.select(
      '''SELECT * FROM outbox WHERE state<>'acknowledged'
      AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions)''',
    )) {
      dirty.add((row['entity_type'] as String, row['entity_id'] as String));
      final p = jsonDecode(row['payload'] as String) as Map;
      if (p['bathroom'] case final String bathroom) {
        dirty.add(('bathroom', bathroom));
      }
      if (p['visit'] case final Map visit) {
        dirty.add(('visit', visit['id'] as String));
      }
      if (p['review'] case final Map review) {
        dirty.add(('visit', review['visit'] as String));
        dirty.add(('bathroom', review['bathroom'] as String));
      }
      if (p['deletedReviewId'] case final String id) dirty.add(('review', id));
    }
    // A pending review also protects its parent against remote deletion.
    for (final r in db.select('SELECT id,visit FROM reviews')) {
      if (dirty.contains(('review', r['id']))) {
        dirty.add(('visit', r['visit'] as String));
      }
    }
    int time(Object? value) =>
        DateTime.parse(value as String).microsecondsSinceEpoch;
    void upsert(String table, Map<String, Object?> values) {
      final columns = values.keys.toList();
      db.execute(
        'INSERT INTO $table (${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) '
        'ON CONFLICT(id) DO UPDATE SET ${columns.skip(1).map((c) => '$c=excluded.$c').join(',')}',
        values.values.toList(),
      );
    }

    for (final type in [
      'sharedBathroom',
      'bathroom',
      'visit',
      'review',
      'favourite',
    ]) {
      for (final row in db.select(
        'SELECT * FROM remote_records WHERE entity_type=? ORDER BY revision',
        [type],
      )) {
        final id = row['entity_id'] as String;
        if (dirty.contains((type, id))) continue;
        // A bounded historical page can lag an acknowledgment or conflict.
        // Never replace newer local knowledge with that older cache snapshot.
        if ((row['revision'] as int) < (sync.revision(type, id) ?? 0)) continue;
        final p = Map<String, Object?>.from(
          jsonDecode(row['payload'] as String) as Map,
        );
        final deleted = row['deleted'] == 1;
        final table = switch (type) {
          'bathroom' || 'sharedBathroom' => 'bathrooms',
          'visit' => 'visits',
          'review' => 'reviews',
          _ => 'favourites',
        };
        if (type != 'favourite') {
          final existing = db.select(
            'SELECT provenance FROM $table WHERE id=?',
            [id],
          );
          if (existing.isNotEmpty &&
              [
                Provenance.demo.value,
                Provenance.unclassifiedLegacy.value,
              ].contains(existing.single['provenance'])) {
            continue;
          }
        }
        if (deleted) {
          if (type == 'visit') local.removeVisit(id);
          if (type == 'review') {
            db.execute('DELETE FROM reviews WHERE id=?', [id]);
          }
          // No bathroom deletion command exists in A2. Retain a referenced parent.
          if (type == 'bathroom' &&
              db.select('SELECT id FROM catalogue_bathrooms WHERE id=?', [
                id,
              ]).isEmpty) {
            db.execute('DELETE FROM favourites WHERE bathroom=?', [id]);
            db.execute(
              'DELETE FROM bathrooms WHERE id=? AND NOT EXISTS(SELECT 1 FROM visits WHERE bathroom=?)',
              [id, id],
            );
          }
          continue;
        }
        if (p.isEmpty) continue;
        if (type == 'sharedBathroom') {
          local.materializeSharedBathroom(
            Bathroom(
              id: id,
              name: p['name'] as String,
              createdBy: 'catalogue',
              emoji: p['emoji'] as String,
              accent: p['accent'] as int,
              accentRgb: p['accent_rgb'] as int?,
              classification: p['classification'] as String?,
            ),
          );
        } else if (type == 'bathroom') {
          if (p['contributor_id'] != local.namespace.subject) {
            throw StateError('Foreign account bathroom');
          }
          upsert(table, {
            'id': id,
            'name': p['name'],
            'normalized_name': (p['name'] as String)
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ')
                .toLowerCase(),
            'creator': p['contributor_id'],
            'emoji': p['emoji'],
            'accent': p['accent'],
            'accent_rgb': p['accent_rgb'],
            'provenance': 'remote',
          });
        } else if (type == 'visit') {
          if (p['owner_id'] != local.namespace.subject) {
            throw StateError('Foreign account visit');
          }
          if (db.select('SELECT id FROM bathrooms WHERE id=?', [
            p['bathroom_id'],
          ]).isEmpty) {
            continue;
          }
          upsert(table, {
            'id': id,
            'bathroom': p['bathroom_id'],
            'user': p['owner_id'],
            'at': time(p['visited_at']),
            'provenance': 'remote',
          });
        } else if (type == 'review') {
          if (p['author_id'] != local.namespace.subject) {
            throw StateError('Invalid private review');
          }
          if (db.select('SELECT id FROM visits WHERE id=?', [
            p['visit_id'],
          ]).isEmpty) {
            continue;
          }
          upsert(table, {
            'id': id,
            'visit': p['visit_id'],
            'bathroom': p['bathroom_id'],
            'author': p['author_id'],
            'created': time(p['created_at']),
            'updated': time(p['updated_at']),
            'rating': p['rating'],
            'paper': p['paper'],
            'hygiene': p['hygiene'],
            'comfort': p['comfort'],
            'aesthetics': p['aesthetics'],
            'tags': jsonEncode([
              for (final t in p['tags'] as List)
                {'emoji': (t as Map)['emoji'], 'label': t['label']},
            ]),
            'comment': p['comment'],
            'provenance': 'remote',
          });
        } else {
          if (db.select('SELECT id FROM bathrooms WHERE id=?', [id]).isEmpty) {
            continue;
          }
          local.setFavourite(
            local.namespace.subject,
            id,
            p['value'] == true || p['owner_id'] == local.namespace.subject,
          );
        }
      }
    }
    for (final row in db.select(
      "SELECT * FROM remote_records WHERE entity_type='link' AND deleted=0",
    )) {
      final id = row['entity_id'] as String;
      if (dirty.contains(('link', id))) continue;
      final p = jsonDecode(row['payload'] as String) as Map;
      if (db.select('SELECT id FROM bathrooms WHERE id IN (?,?)', [
            id,
            p['shared_id'],
          ]).length ==
          2) {
        db.execute(
          'INSERT INTO bathroom_links VALUES(?,?) ON CONFLICT(private_id) DO UPDATE SET shared_id=excluded.shared_id',
          [id, p['shared_id']],
        );
      }
    }
    // Validate domain constructors before committing the projection.
    local.load();
  });
}
