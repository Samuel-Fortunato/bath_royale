import 'dart:convert';
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

/// No implicit authorization: only explicit test repositories use this context.
class SyncWriteContext {
  final DataNamespace namespace;
  const SyncWriteContext.forTesting(this.namespace);
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
        revision(type, id),
      ],
    );
    for (final (parentType, parentId) in [(type, id), ...references]) {
      final rows = db.select(
        '''SELECT operation_id FROM outbox WHERE entity_type=? AND entity_id=?
        AND operation_id<>? AND state<>'acknowledged' ORDER BY sequence DESC LIMIT 1''',
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
      '''INSERT INTO remote_records VALUES(?,?,0,1,'{}')
      ON CONFLICT(entity_type,entity_id) DO UPDATE SET deleted=1''',
      [type, id],
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
        WHERE excluded.revision>remote_records.revision AND remote_records.deleted=0''',
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
}
