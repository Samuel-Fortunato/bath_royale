import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../storage/local_store.dart';
import 'namespace.dart';

class OutboxOperation {
  final String id, entityType, entityId, type, payload;
  final DataNamespace namespace;
  final int? baseRevision;
  final int attempts;
  final Map<String, int> dependencies;
  OutboxOperation.fromRow(
    Map<String, Object?> row,
    this.namespace, {
    Map<String, int> dependencies = const {},
  }) : id = row['operation_id'] as String,
       entityType = row['entity_type'] as String,
       entityId = row['entity_id'] as String,
       type = row['operation_type'] as String,
       payload = row['payload'] as String,
       baseRevision = row['base_revision'] as int?,
       attempts = row['attempts'] as int,
       dependencies = Map.unmodifiable(dependencies);
}

class RemoteChange {
  final String entityType, entityId;
  final int revision;
  final bool deleted;
  final Map<String, Object?> payload;
  RemoteChange(
    this.entityType,
    this.entityId,
    this.revision, {
    this.deleted = false,
    Map<String, Object?> payload = const {},
  }) : payload = Map.unmodifiable(payload) {
    if (revision < 0) throw ArgumentError('Negative revision');
  }
}

/// Permits durable local queueing only; remote transfer requires separate consent.
class SyncWriteContext {
  final DataNamespace namespace;
  const SyncWriteContext.forTesting(this.namespace);
  const SyncWriteContext.account(this.namespace);
}

class SyncStore {
  final LocalStore local;
  SyncStore(this.local);
  DataNamespace get namespace => local.namespace;

  int? revision(String type, String id) {
    final rows = local.database.select(
      'SELECT MAX(revision) AS revision FROM (SELECT revision FROM remote_records WHERE entity_type=? AND entity_id=? UNION ALL SELECT revision FROM server_revisions WHERE entity_type=? AND entity_id=?)',
      [type, id, type, id],
    );
    return rows.single['revision'] as int?;
  }

  /// Called inside the same transaction as the domain mutation.
  void enqueue(
    String type,
    String id,
    String command,
    Map<String, Object?> payload, {
    List<(String, String)> references = const [],
  }) {
    if (!namespace.isAccount) throw StateError('Account scope required');
    final db = local.database;
    final operationId = const Uuid().v4();
    // A cached remote advance is not consent to overwrite an unseen concurrent
    // edit while this entity still has an unresolved local predecessor.
    final previous = db.select(
      '''SELECT base_revision FROM outbox WHERE entity_type=? AND entity_id=?
      AND state<>'acknowledged' AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions)
      ORDER BY sequence DESC LIMIT 1''',
      [type, id],
    );
    final base = previous.isEmpty
        ? revision(type, id)
        : previous.single['base_revision'];
    db.execute(
      '''INSERT INTO outbox(operation_id,scope,entity_type,entity_id,operation_type,payload,base_revision)
      VALUES(?,?,?,?,?,?,?)''',
      [
        operationId,
        namespace.key,
        type,
        id,
        command,
        jsonEncode(payload),
        base,
      ],
    );
    for (final (parentType, parentId) in [(type, id), ...references]) {
      final rows = db.select(
        '''SELECT operation_id FROM outbox WHERE entity_type=? AND entity_id=?
        AND operation_id<>? AND state<>'acknowledged' AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions) ORDER BY sequence DESC LIMIT 1''',
        [parentType, parentId, operationId],
      );
      if (rows.isNotEmpty) {
        db.execute('INSERT OR IGNORE INTO outbox_dependencies VALUES(?,?)', [
          operationId,
          rows.single['operation_id'],
        ]);
      }
    }
  }

  List<OutboxOperation> ready(int now, int limit) => local.database
      .select(
        '''
    SELECT o.* FROM outbox o WHERE scope=? AND state='pending' AND next_attempt<=?
    AND NOT EXISTS(SELECT 1 FROM outbox_dependencies d JOIN outbox p ON p.operation_id=d.dependency_id
      WHERE d.operation_id=o.operation_id AND p.state<>'acknowledged')
    AND o.operation_id NOT IN (SELECT operation_id FROM sync_resolutions)
    ORDER BY sequence LIMIT ?''',
        [namespace.key, now, limit],
      )
      .map(
        (r) => OutboxOperation.fromRow(
          r,
          namespace,
          dependencies: {
            for (final d in local.database.select(
              '''SELECT p.operation_id,p.acknowledged_revision FROM outbox_dependencies d
          JOIN outbox p ON p.operation_id=d.dependency_id WHERE d.operation_id=? ORDER BY p.operation_id''',
              [r['operation_id']],
            ))
              d['operation_id'] as String: d['acknowledged_revision'] as int,
          },
        ),
      )
      .toList();

  void _checkOperation(OutboxOperation op) {
    if (op.namespace != namespace) {
      throw StateError('Operation namespace mismatch');
    }
    final rows = local.database.select(
      "SELECT * FROM outbox WHERE operation_id=? AND scope=? AND state='pending'",
      [op.id, namespace.key],
    );
    if (rows.length != 1 ||
        rows.single['entity_type'] != op.entityType ||
        rows.single['entity_id'] != op.entityId ||
        rows.single['operation_type'] != op.type ||
        rows.single['payload'] != op.payload ||
        rows.single['base_revision'] != op.baseRevision) {
      throw StateError('Operation does not match pending durable input');
    }
  }

  void retry(OutboxOperation op, int next, String error) =>
      local.transaction(() {
        _checkOperation(op);
        local.database.execute(
          '''UPDATE outbox SET attempts=attempts+1,next_attempt=?,error=?
      WHERE operation_id=? AND scope=? AND state='pending' ''',
          [next, error, op.id, namespace.key],
        );
      });

  void acknowledge(OutboxOperation op, int revision) => local.transaction(() {
    _checkOperation(op);
    if (revision < 0) throw StateError('Invalid acknowledgment revision');
    local.database.execute(
      '''UPDATE outbox SET state='acknowledged',acknowledged_revision=?,error=NULL
      WHERE operation_id=? AND scope=? AND state='pending' ''',
      [revision, op.id, namespace.key],
    );
    // Canonical snapshots are received through pull. An ack only advances the revision.
    final body = jsonDecode(op.payload) as Map<String, dynamic>;
    final targets = <(String, String)>[(op.entityType, op.entityId)];
    if (body['visit'] case final Map<String, dynamic> visit) {
      targets.add(('visit', visit['id'] as String));
    }
    if (body['review'] case final Map<String, dynamic> review) {
      targets.add(('visit', review['visit'] as String));
    }
    if (body['deletedReviewId'] case final String id) {
      targets.add(('review', id));
    }
    for (final (type, id) in targets) {
      final deleted = op.type == 'deleteVisit';
      _advanceRevision(type, id, revision);
      if (deleted) tombstone(type, id);
    }
  });

  void _advanceRevision(String type, String id, int revision) {
    local.database.execute(
      '''INSERT INTO server_revisions VALUES(?,?,?)
      ON CONFLICT(entity_type,entity_id) DO UPDATE SET revision=MAX(revision,excluded.revision)''',
      [type, id, revision],
    );
  }

  void reject(
    OutboxOperation op,
    String error, {
    RemoteChange? conflict,
  }) => local.transaction(() {
    _checkOperation(op);
    local.database.execute(
      'UPDATE outbox SET state=?,error=? WHERE operation_id=? AND scope=?',
      [conflict == null ? 'rejected' : 'conflict', error, op.id, namespace.key],
    );
    if (conflict != null) {
      if (conflict.entityType != op.entityType ||
          conflict.entityId != op.entityId) {
        throw StateError('Conflict identity mismatch');
      }
      local.database
          .execute('INSERT OR REPLACE INTO sync_conflicts VALUES(?,?,?,?)', [
            op.id,
            conflict.revision,
            jsonEncode(conflict.payload),
            conflict.deleted ? 1 : 0,
          ]);
      _advanceRevision(op.entityType, op.entityId, conflict.revision);
      if (conflict.deleted) tombstone(op.entityType, op.entityId);
    }
  });

  void tombstone(String type, String id) {
    local.database.execute(
      '''INSERT INTO remote_records VALUES(?,?,?,1,'{}')
      ON CONFLICT(entity_type,entity_id) DO UPDATE SET
        revision=MAX(remote_records.revision,excluded.revision),deleted=1,payload='{}'
      ''',
      [type, id, revision(type, id) ?? 0],
    );
  }

  bool pullAllowed(String feed, int now) {
    _checkFeed(feed);
    final rows = local.database.select(
      'SELECT * FROM pull_status WHERE feed=?',
      [feed],
    );
    return rows.isEmpty ||
        (rows.single['blocked'] == 0 &&
            (rows.single['next_attempt'] as int) <= now);
  }

  int pullAttempts(String feed) {
    final rows = local.database.select(
      'SELECT attempts FROM pull_status WHERE feed=?',
      [feed],
    );
    return rows.isEmpty ? 0 : rows.single['attempts'] as int;
  }

  void failPull(String feed, String error, int next, {bool blocked = false}) =>
      local.transaction(() {
        _checkFeed(feed);
        local.database.execute(
          '''INSERT INTO pull_status VALUES(?,1,?,?,?)
      ON CONFLICT(feed) DO UPDATE SET attempts=attempts+1,next_attempt=excluded.next_attempt,
      error=excluded.error,blocked=excluded.blocked''',
          [feed, next, error, blocked ? 1 : 0],
        );
      });
  void retryPull(String feed) => local.transaction(() {
    _checkFeed(feed);
    local.database.execute('DELETE FROM pull_status WHERE feed=?', [feed]);
  });

  String? checkpoint(String feed) {
    _checkFeed(feed);
    final rows = local.database.select(
      'SELECT checkpoint FROM pull_checkpoints WHERE feed=?',
      [feed],
    );
    return rows.isEmpty ? null : rows.single['checkpoint'] as String;
  }

  void _checkFeed(String feed) {
    if ((namespace.kind == 'public' && feed == 'catalogue') ||
        (namespace.isAccount && feed == 'private')) {
      return;
    }
    throw StateError('Feed does not belong to namespace');
  }

  /// Remote cache is separate from local drafts; pulls never overwrite domain rows.
  void applyPull(
    String feed,
    List<RemoteChange> changes,
    String checkpoint,
  ) => local.transaction(() {
    _checkFeed(feed);
    for (final c in changes) {
      _advanceRevision(c.entityType, c.entityId, c.revision);
      local.database.execute(
        '''INSERT INTO remote_records VALUES(?,?,?,?,?)
        ON CONFLICT(entity_type,entity_id) DO UPDATE SET revision=excluded.revision,
        deleted=excluded.deleted,payload=excluded.payload
        WHERE excluded.revision>remote_records.revision AND
          (remote_records.deleted=0 OR json_extract(remote_records.payload,'\$._visibility')=0)''',
        [
          c.entityType,
          c.entityId,
          c.revision,
          c.deleted ? 1 : 0,
          jsonEncode(c.payload),
        ],
      );
    }
    local.database.execute(
      'INSERT INTO pull_checkpoints VALUES(?,?) ON CONFLICT(feed) DO UPDATE SET checkpoint=excluded.checkpoint',
      [feed, checkpoint],
    );
    local.database.execute('DELETE FROM pull_status WHERE feed=?', [feed]);
  });
  bool get hasConsent => local.database
      .select(
        'SELECT consent_version FROM sync_preferences WHERE id=1 AND consent_version=1',
      )
      .isNotEmpty;

  /// This is the sole first-upload permission, scoped to this account/device.
  /// Backfill only genuine account rows, never guest/demo/unknown provenance.
  void consent() => local.transaction(() {
    if (!namespace.isAccount) throw StateError('Account required');
    for (final (type, table, actor, command) in [
      ('bathroom', 'bathrooms', 'creator', 'createBathroom'),
      ('visit', 'visits', 'user', 'createVisit'),
      ('review', 'reviews', 'author', 'createReview'),
    ]) {
      for (final row in local.database.select(
        "SELECT * FROM $table WHERE provenance='user_created' AND $actor=?",
        [namespace.subject],
      )) {
        final id = row['id'] as String;
        if (revision(type, id) != null ||
            local.database.select(
              'SELECT operation_id FROM outbox WHERE entity_type=? AND entity_id=?',
              [type, id],
            ).isNotEmpty) {
          continue;
        }
        if (type != 'bathroom' &&
            local.database.select(
              "SELECT id FROM bathrooms WHERE id=? AND creator=? AND provenance IN ('user_created','remote')",
              [row['bathroom'], namespace.subject],
            ).isEmpty) {
          continue;
        }
        final payload = Map<String, Object?>.from(row);
        enqueue(
          type,
          id,
          command,
          type == 'review' ? {'review': payload} : payload,
          references: [
            if (type != 'bathroom') ('bathroom', row['bathroom'] as String),
            if (type == 'review') ('visit', row['visit'] as String),
          ],
        );
      }
    }
    for (final row in local.database.select(
      "SELECT f.* FROM favourites f JOIN bathrooms b ON b.id=f.bathroom WHERE f.user=? AND f.provenance='user_created' AND b.creator=? AND b.provenance IN ('user_created','remote')",
      [namespace.subject, namespace.subject],
    )) {
      final id = row['bathroom'] as String;
      if (revision('favourite', id) == null &&
          local.database.select(
            "SELECT operation_id FROM outbox WHERE entity_type='favourite' AND entity_id=?",
            [id],
          ).isEmpty) {
        enqueue(
          'favourite',
          id,
          'setFavourite',
          {'user': namespace.subject, 'bathroom': id, 'value': true},
          references: [('bathroom', id)],
        );
      }
    }
    local.database.execute(
      'INSERT OR REPLACE INTO sync_preferences VALUES(1,1)',
    );
  });

  int get pendingCount =>
      local.database
              .select(
                "SELECT count(*) n FROM outbox WHERE state='pending' AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions)",
              )
              .single['n']
          as int;

  List<Map<String, Object?>> get problems => [
    for (final r in local.database.select(
      '''SELECT o.*,c.remote_payload,c.remote_deleted,c.remote_revision FROM outbox o
    LEFT JOIN sync_conflicts c USING(operation_id) WHERE o.state IN ('rejected','conflict')
    AND o.operation_id NOT IN (SELECT operation_id FROM sync_resolutions) ORDER BY sequence''',
    ))
      Map.of(r),
  ];

  List<Map<String, Object?>> get archives => [
    for (final r in local.database.select(
      '''SELECT o.*,s.resolution FROM outbox o JOIN sync_resolutions s USING(operation_id) ORDER BY sequence''',
    ))
      Map.of(r),
  ];

  bool get pullBlocked => local.database
      .select("SELECT feed FROM pull_status WHERE feed='private' AND blocked=1")
      .isNotEmpty;

  int? get nextAttempt {
    final next =
        local.database
                .select(
                  "SELECT min(next_attempt) n FROM outbox WHERE state='pending' AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions) AND NOT EXISTS(SELECT 1 FROM outbox_dependencies d JOIN outbox p ON p.operation_id=d.dependency_id WHERE d.operation_id=outbox.operation_id AND p.state<>'acknowledged')",
                )
                .single['n']
            as int?;
    final pull = local.database.select(
      "SELECT next_attempt FROM pull_status WHERE feed='private' AND blocked=0",
    );
    final p = pull.isEmpty ? null : pull.single['next_attempt'] as int;
    return next == null
        ? p
        : p == null || next < p
        ? next
        : p;
  }

  void resetPrivateCheckpoint() => local.transaction(() {
    if (!namespace.isAccount) throw StateError('Account required');
    local.database.execute("DELETE FROM pull_checkpoints WHERE feed='private'");
    local.database.execute("DELETE FROM pull_status WHERE feed='private'");
  });

  void retryNow() => local.transaction(() {
    local.database.execute(
      "UPDATE outbox SET next_attempt=0 WHERE state='pending'",
    );
    local.database.execute("DELETE FROM pull_status WHERE feed='private'");
  });

  /// Preserve immutable submitted input; a human retry always gets a new ID.
  void retryProblem(
    String operationId, {
    String? correctedText,
  }) => local.transaction(() {
    final row = problems.singleWhere((r) => r['operation_id'] == operationId);
    if (row['remote_deleted'] == 1) {
      throw StateError('Deleted identities cannot be restored');
    }
    var payload = row['payload'] as String;
    if (correctedText != null) {
      final p = jsonDecode(payload) as Map<String, dynamic>;
      if (p['name'] != null) {
        final text = correctedText.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty ||
            text.characters.length > 100 ||
            text.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
          throw ArgumentError('Invalid bathroom name');
        }
        p['name'] = text;
        if (p.containsKey('normalized_name')) {
          p['normalized_name'] = text.toLowerCase();
        }
        local.database.execute(
          'UPDATE bathrooms SET name=?,normalized_name=? WHERE id=?',
          [text, text.toLowerCase(), row['entity_id']],
        );
      } else if (p['review'] case final Map<String, dynamic> review) {
        final text = correctedText.trim();
        if (text.characters.length > 500 || text.contains('\u0000')) {
          throw ArgumentError('Invalid comment');
        }
        review['comment'] = text.isEmpty ? null : text;
        local.database.execute('UPDATE reviews SET comment=? WHERE id=?', [
          review['comment'],
          row['entity_id'],
        ]);
      } else {
        throw ArgumentError('No editable text');
      }
      payload = jsonEncode(p);
    }
    final id = const Uuid().v4();
    local.database.execute(
      '''INSERT INTO outbox(operation_id,scope,entity_type,entity_id,operation_type,payload,base_revision)
    VALUES(?,?,?,?,?,?,?)''',
      [
        id,
        namespace.key,
        row['entity_type'],
        row['entity_id'],
        row['operation_type'],
        payload,
        row['remote_revision'] ?? row['base_revision'],
      ],
    );
    local.database.execute('INSERT INTO sync_resolutions VALUES(?,?)', [
      operationId,
      'retried',
    ]);
    // Preserve the original observed causal base; a newer unseen cache is not
    // permission to overwrite another device's intervening edit.
    local.database.execute(
      'INSERT INTO outbox_dependencies SELECT ?,dependency_id FROM outbox_dependencies WHERE operation_id=?',
      [id, operationId],
    );
    local.database.execute(
      'UPDATE outbox_dependencies SET dependency_id=? WHERE dependency_id=?',
      [id, operationId],
    );
  });

  /// The whole dependent branch is archived, never deleted or uploaded later.
  void useAccountVersion(String operationId) => local.transaction(() {
    if (!problems.any((r) => r['operation_id'] == operationId)) {
      throw StateError('Unknown problem');
    }
    final original = problems.singleWhere(
      (r) => r['operation_id'] == operationId,
    );
    if (original['entity_type'] == 'link') {
      local.database.execute('DELETE FROM bathroom_links WHERE private_id=?', [
        original['entity_id'],
      ]);
    }
    if (original['entity_type'] == 'contribution' &&
        local.database.select('SELECT id FROM visits WHERE bathroom=?', [
          original['entity_id'],
        ]).isEmpty &&
        local.database.select('SELECT user FROM favourites WHERE bathroom=?', [
          original['entity_id'],
        ]).isEmpty) {
      local.database.execute('DELETE FROM catalogue_bathrooms WHERE id=?', [
        original['entity_id'],
      ]);
      local.database.execute('DELETE FROM bathrooms WHERE id=?', [
        original['entity_id'],
      ]);
    }
    final branch = local.database.select(
      '''WITH RECURSIVE branch(id) AS (SELECT ? UNION
      SELECT d.operation_id FROM outbox_dependencies d JOIN branch b ON d.dependency_id=b.id)
      SELECT id FROM branch''',
      [operationId],
    );
    for (final row in branch) {
      local.database.execute(
        'INSERT OR IGNORE INTO sync_resolutions VALUES(?,?)',
        [row['id'], 'account_version'],
      );
    }
  });
}
