import 'dart:convert';
import 'package:uuid/uuid.dart';

/// A database is permanently bound to one scope. Subjects are stable auth IDs.
class DataNamespace {
  final String kind;
  final String environment;
  final String subject;
  const DataNamespace.guest() : kind = 'guest', environment = '', subject = '';
  DataNamespace.account(this.environment, this.subject) : kind = 'account' {
    if (environment.isEmpty || subject.isEmpty) {
      throw ArgumentError('Environment and subject are required');
    }
  }
  DataNamespace.publicCatalogue(this.environment)
    : kind = 'public',
      subject = '' {
    if (environment.isEmpty) throw ArgumentError('Environment is required');
  }
  String get key => jsonEncode([kind, environment, subject]);
  String get fileName => kind == 'guest'
      ? 'bath_royale.sqlite'
      : 'bath_royale_${const Uuid().v5(Namespace.url.value, key)}.sqlite';
  bool get isAccount => kind == 'account';
  @override
  bool operator ==(Object other) => other is DataNamespace && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

const syncSchemaV6 = '''
CREATE TABLE namespace (id INTEGER PRIMARY KEY CHECK(id=1), scope TEXT NOT NULL);
CREATE TABLE outbox (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT NOT NULL UNIQUE,
 scope TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 operation_type TEXT NOT NULL, payload TEXT NOT NULL, base_revision INTEGER,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','acknowledged','rejected','conflict')),
 attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL DEFAULT 0,
 error TEXT, acknowledged_revision INTEGER);
CREATE TABLE outbox_dependencies (
 operation_id TEXT NOT NULL REFERENCES outbox(operation_id),
 dependency_id TEXT NOT NULL REFERENCES outbox(operation_id),
 PRIMARY KEY(operation_id,dependency_id), CHECK(operation_id<>dependency_id));
CREATE TABLE server_revisions (entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(revision>=0), PRIMARY KEY(entity_type,entity_id));
CREATE TABLE remote_records (
 entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(revision>=0), deleted INTEGER NOT NULL CHECK(deleted IN (0,1)),
 payload TEXT NOT NULL, PRIMARY KEY(entity_type,entity_id));
CREATE TABLE sync_conflicts (
 operation_id TEXT PRIMARY KEY REFERENCES outbox(operation_id),
 remote_revision INTEGER NOT NULL, remote_payload TEXT NOT NULL,
 remote_deleted INTEGER NOT NULL CHECK(remote_deleted IN (0,1)));
CREATE TABLE pull_status (feed TEXT PRIMARY KEY, attempts INTEGER NOT NULL,
 next_attempt INTEGER NOT NULL, error TEXT NOT NULL, blocked INTEGER NOT NULL CHECK(blocked IN (0,1)));
CREATE TABLE pull_checkpoints (feed TEXT PRIMARY KEY, checkpoint TEXT NOT NULL);
''';
