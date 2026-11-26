import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';

void main() {
  final scope = DataNamespace.account('test-environment', 'subject-A');
  late LocalStore local;
  late BathroomRepository repository;
  late SyncStore sync;
  late FakeAuthSession auth;
  late FakeRemoteDataSource remote;
  late SyncCoordinator coordinator;
  var now = 10000;
  Bathroom bathroom([String id = 'b']) =>
      Bathroom(id: id, name: 'Bathroom $id', createdBy: scope.subject);
  Visit visit([String id = 'v']) => Visit(
    id: id,
    bathroomId: 'b',
    userId: scope.subject,
    visitedAt: DateTime.utc(2030),
  );
  Review review(Visit v) => Review(
    id: 'r',
    visitId: v.id,
    bathroomId: v.bathroomId,
    authorId: v.userId,
    createdAt: v.visitedAt,
    rating: 3,
    paperAvailability: 1,
    hygiene: 2,
    comfort: 3,
    aesthetics: 4,
    tags: ['Bom'],
    comment: 'Draft',
  );
  List<Map<String, Object?>> rows(String table) => local.database
      .select('SELECT * FROM $table')
      .map((r) => Map<String, Object?>.of(r))
      .toList();
  void reconnect() {
    sync = SyncStore(local);
    repository = BathroomRepository(
      local,
      syncContext: SyncWriteContext.forTesting(scope),
    );
    coordinator = SyncCoordinator(
      store: sync,
      auth: auth,
      remote: remote,
      now: () => now,
      jitter: () => 1,
    );
  }

  setUp(() {
    now = 10000;
    local = LocalStore(sqlite3.openInMemory(), namespace: scope);
    auth = FakeAuthSession()..change(SessionIdentity(scope, 100000000));
    remote = FakeRemoteDataSource();
    reconnect();
  });
  tearDown(() => local.close());

  test(
    'guest remains offline; notifications, reads, theme and ordinary mutations never enqueue',
    () {
      final guest = LocalStore(sqlite3.openInMemory());
      addTearDown(guest.close);
      final app = AppState.restore(guest);
      addTearDown(app.dispose);
      final b = app.createBathroom('Local');
      app.recordVisit(b.id, visitedAt: DateTime.utc(2030));
      app.toggleFavorite(b.id);
      app.toggleTheme();
      app.notifyListeners();
      app.entries;
      guest.load();
      expect(guest.database.select('SELECT * FROM outbox'), isEmpty);
      expect(
        () => BathroomRepository(
          guest,
          syncContext: SyncWriteContext.forTesting(scope),
        ),
        throwsArgumentError,
      );
      expect(remote.requests, isEmpty);
    },
  );

  test(
    'v5 guest upgrade preserves exact rows and never associates or queues them',
    () {
      final dir = Directory.systemTemp.createTempSync('sync-v5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/old.sqlite';
      final old = LocalStore(sqlite3.open(path));
      final app = AppState.restore(old);
      final b = app.createBathroom('Genuine old');
      app.recordVisit(b.id, visitedAt: DateTime.utc(2030));
      app.toggleFavorite(b.id);
      app.toggleTheme();
      old.database.execute(
        "UPDATE bathrooms SET provenance='unclassified_legacy' WHERE id=?",
        [b.id],
      );
      final before = <String, List<List<Object?>>>{};
      for (final table in [
        'bathrooms',
        'visits',
        'reviews',
        'favourites',
        'settings',
        'metadata',
      ]) {
        before[table] = old.database
            .select('SELECT * FROM $table')
            .map((r) => r.values.toList())
            .toList();
      }
      for (final table in [
        'sync_conflicts',
        'outbox_dependencies',
        'outbox',
        'remote_records',
        'server_revisions',
        'pull_checkpoints',
        'pull_status',
        'namespace',
      ]) {
        old.database.execute('DROP TABLE $table');
      }
      old.database.userVersion = 5;
      app.dispose();
      old.close();
      expect(
        () => LocalStore(sqlite3.open(path), namespace: scope),
        throwsStateError,
      );
      final unchanged = sqlite3.open(path);
      expect(unchanged.userVersion, 5);
      unchanged.close();
      final upgraded = LocalStore(sqlite3.open(path));
      addTearDown(upgraded.close);
      expect(upgraded.namespace, const DataNamespace.guest());
      for (final table in before.keys) {
        expect(
          upgraded.database
              .select('SELECT * FROM $table')
              .map((r) => r.values.toList()),
          before[table],
        );
      }
      expect(upgraded.database.userVersion, 6);
      expect(upgraded.database.select('SELECT * FROM outbox'), isEmpty);
    },
  );

  test(
    'persistent files isolate identical entity IDs across account, environment, guest and public scopes',
    () {
      final dir = Directory.systemTemp.createTempSync('scopes');
      addTearDown(() => dir.deleteSync(recursive: true));
      final scopes = [
        scope,
        DataNamespace.account('test-environment', 'subject-B'),
        DataNamespace.account('other', 'subject-A'),
        const DataNamespace.guest(),
        DataNamespace.publicCatalogue('test-environment'),
      ];
      expect(scopes.map((s) => s.fileName).toSet().length, scopes.length);
      for (final s in scopes) {
        final path = '${dir.path}/${s.fileName}';
        final db = LocalStore(sqlite3.open(path), namespace: s);
        if (s.isAccount) {
          BathroomRepository(
            db,
            syncContext: SyncWriteContext.forTesting(s),
          ).createBathroom(
            Bathroom(id: 'b', name: 'Private ${s.key}', createdBy: s.subject),
          );
        }
        db.close();
        expect(
          () => LocalStore(
            sqlite3.open(path),
            namespace: DataNamespace.account('wrong', 'wrong'),
          ),
          throwsStateError,
        );
        final reopened = LocalStore(sqlite3.open(path), namespace: s);
        expect(
          reopened.database.select('SELECT * FROM outbox').length,
          s.isAccount ? 1 : 0,
        );
        expect(
          reopened.database.select('SELECT * FROM bathrooms').length,
          s.isAccount ? 1 : 0,
        );
        expect(
          reopened.load()?.bathrooms.length,
          s.isAccount ? 1 : (s.kind == 'public' ? 0 : null),
        );
        reopened.close();
      }
    },
  );

  test('wrong actor cannot mutate an account store', () {
    expect(
      () => repository.createBathroom(
        Bathroom(id: 'b', name: 'Wrong', createdBy: 'subject-B'),
      ),
      throwsStateError,
    );
    expect(rows('bathrooms'), isEmpty);
    expect(rows('outbox'), isEmpty);
  });

  test(
    'outbox insertion failure rolls back entity and compound visit/review',
    () {
      repository.createBathroom(bathroom());
      local.database.execute(
        "CREATE TRIGGER fail_queue BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      expect(
        () => repository.createBathroom(bathroom('second')),
        throwsA(isA<SqliteException>()),
      );
      expect(rows('bathrooms').length, 1);
      final v = visit();
      expect(
        () => repository.saveReview(review(v), newVisit: v, isNew: true),
        throwsA(isA<SqliteException>()),
      );
      expect(rows('visits'), isEmpty);
      expect(rows('reviews'), isEmpty);
      expect(rows('outbox').length, 1);
    },
  );

  test(
    'compound review has one durable command; favourites carry desired booleans',
    () {
      repository.createBathroom(bathroom());
      final v = visit();
      repository.saveReview(review(v), newVisit: v, isNew: true);
      repository.setFavourite(scope.subject, 'b', true);
      repository.setFavourite(scope.subject, 'b', false);
      final ops = rows('outbox');
      expect(ops.map((o) => o['operation_type']), [
        'createBathroom',
        'createVisitReview',
        'setFavourite',
        'setFavourite',
      ]);
      expect(
        jsonDecode(ops[1]['payload'] as String).keys,
        containsAll(['visit', 'review']),
      );
      expect(
        ops.skip(2).map((o) => jsonDecode(o['payload'] as String)['value']),
        [true, false],
      );
    },
  );

  test('fictional, legacy and remote cache mutations do not enqueue', () {
    for (final provenance in ['demo', 'unclassified_legacy', 'remote']) {
      local.database.execute("INSERT INTO bathrooms VALUES(?,?,?,?,'🚽',0,?)", [
        provenance,
        provenance,
        provenance,
        scope.subject,
        provenance,
      ]);
      if (provenance == 'remote') continue;
      final v = Visit(
        id: provenance,
        bathroomId: provenance,
        userId: scope.subject,
        visitedAt: DateTime.utc(2030),
      );
      repository.recordVisit(v);
      repository.setFavourite(scope.subject, provenance, true);
    }
    sync.applyPull('private', [RemoteChange('review', 'cache', 4)], 'page');
    repository.setDarkMode(false);
    expect(rows('outbox'), isEmpty);
  });

  test(
    'restart retries lost acknowledgments with unchanged operation ID and no duplicate remote effect',
    () async {
      local.close();
      final dir = Directory.systemTemp.createTempSync('pending');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/pending.sqlite';
      local = LocalStore(sqlite3.open(path), namespace: scope);
      reconnect();
      repository.createBathroom(bathroom());
      final id = rows('outbox').single['operation_id'];
      remote.loseNextAcknowledgment = true;
      await coordinator.synchronize();
      expect(rows('outbox').single['attempts'], 1);
      local.close();
      local = LocalStore(sqlite3.open(path), namespace: scope);
      reconnect();
      await coordinator.synchronize();
      expect(remote.requests.length, 1);
      now += 1000;
      await coordinator.synchronize();
      expect(remote.requests.map((r) => r.id), [id, id]);
      expect(remote.applications, 1);
      expect(rows('outbox').single['state'], 'acknowledged');
    },
  );

  test('interrupted local acknowledgment is retried idempotently', () async {
    repository.createBathroom(bathroom());
    local.database.execute(
      "CREATE TRIGGER fail_ack BEFORE UPDATE ON outbox BEGIN SELECT RAISE(ABORT,'interrupted'); END",
    );
    await expectLater(
      coordinator.synchronize(),
      throwsA(isA<SqliteException>()),
    );
    expect(rows('outbox').single['state'], 'pending');
    expect(rows('remote_records'), isEmpty);
    local.database.execute('DROP TRIGGER fail_ack');
    await coordinator.synchronize();
    expect(remote.applications, 1);
    expect(remote.requests[0].id, remote.requests[1].id);
  });

  test('bounded batches honor parent and same-entity ordering', () async {
    repository.createBathroom(bathroom());
    repository.recordVisit(visit());
    repository.saveReview(review(visit()), isNew: true);
    coordinator = SyncCoordinator(
      store: sync,
      auth: auth,
      remote: remote,
      now: () => now,
      batchSize: 2,
    );
    await coordinator.synchronize();
    expect(remote.requests.map((o) => o.type), [
      'createBathroom',
      'createVisit',
    ]);
    await coordinator.synchronize();
    expect(remote.requests.last.type, 'createReview');
    expect(rows('outbox').every((r) => r['state'] == 'acknowledged'), true);
  });

  test(
    'one execution at a time and switch away/back invalidates in-flight acknowledgment',
    () async {
      repository.createBathroom(bathroom());
      final gate = Completer<void>();
      remote.beforeSubmit = () => gate.future;
      final running = coordinator.synchronize();
      await coordinator.synchronize();
      expect(remote.requests.length, 1);
      auth.change(
        SessionIdentity(
          DataNamespace.account('test-environment', 'subject-B'),
          1000000,
        ),
      );
      auth.change(SessionIdentity(scope, 1000000));
      gate.complete();
      await running;
      expect(rows('outbox').single['state'], 'pending');
      expect(rows('pull_checkpoints'), isEmpty);
      remote.beforeSubmit = null;
      await coordinator.synchronize();
      expect(remote.applications, 1);
      expect(rows('outbox').single['state'], 'acknowledged');
    },
  );

  test(
    'missing, expired and remotely invalid authentication pause without losing work',
    () async {
      repository.createBathroom(bathroom());
      auth.change(null);
      await coordinator.synchronize();
      auth.change(SessionIdentity(scope, now));
      await coordinator.synchronize();
      expect(remote.requests, isEmpty);
      auth.change(SessionIdentity(scope, 100000));
      remote.failures.add(
        const RemoteFailure(RemoteFailureKind.unavailableAuthentication),
      );
      await coordinator.synchronize();
      expect(rows('outbox').single['state'], 'pending');
      expect(rows('outbox').single['attempts'], 0);
      auth.change(SessionIdentity(scope, 100000));
      await coordinator.synchronize();
      expect(rows('outbox').single['state'], 'acknowledged');
    },
  );

  test(
    'transport backoff grows, stays bounded and survives attempts; permanent errors block dependencies',
    () async {
      repository.createBathroom(bathroom());
      repository.recordVisit(visit());
      for (var i = 0; i < 12; i++) {
        remote.failures.add(const RemoteFailure(RemoteFailureKind.transport));
        await coordinator.synchronize();
        final next = rows('outbox').first['next_attempt'] as int;
        expect(next - now, lessThanOrEqualTo(300000));
        expect(next - now, 1000 * (1 << i) > 300000 ? 300000 : 1000 * (1 << i));
        now = next;
      }
      remote.failures.add(const RemoteFailure(RemoteFailureKind.authorization));
      await coordinator.synchronize();
      expect(rows('outbox').first['state'], 'rejected');
      expect(rows('outbox').last['state'], 'pending');
      expect(sync.ready(now, 10), isEmpty);
    },
  );

  test(
    'conflict retains local review draft, payload and explicit remote revision',
    () async {
      repository.createBathroom(bathroom());
      await coordinator.synchronize();
      final v = visit();
      repository.saveReview(review(v), newVisit: v, isNew: true);
      final payload = rows('outbox').last['payload'];
      remote.failures.add(
        RemoteFailure(
          RemoteFailureKind.conflict,
          conflict: RemoteChange(
            'review',
            'r',
            9,
            payload: {'comment': 'Remote'},
          ),
        ),
      );
      await coordinator.synchronize();
      expect(rows('outbox').last['state'], 'conflict');
      expect(rows('outbox').last['payload'], payload);
      expect(rows('reviews').single['comment'], 'Draft');
      expect(rows('visits').single['id'], 'v');
      expect(rows('sync_conflicts').single['remote_revision'], 9);
    },
  );

  test(
    'pull revision and tombstones reject stale updates and preserve pending local drafts',
    () {
      repository.createBathroom(bathroom());
      final v = visit();
      repository.saveReview(review(v), newVisit: v, isNew: true);
      sync.applyPull('private', [
        RemoteChange('review', 'r', 8, payload: {'comment': 'Remote'}),
      ], 'a');
      sync.applyPull('private', [
        RemoteChange('review', 'r', 7, payload: {'comment': 'Stale'}),
      ], 'b');
      expect(rows('remote_records').single['revision'], 8);
      expect(rows('reviews').single['comment'], 'Draft');
      repository.deleteVisit('v');
      sync.applyPull('private', [
        RemoteChange('review', 'r', 99),
        RemoteChange('visit', 'v', 99),
      ], 'c');
      expect(rows('remote_records').every((r) => r['deleted'] == 1), true);
      sync.applyPull('private', [
        RemoteChange('review', 'other', 5, deleted: true),
      ], 'd');
      sync.applyPull('private', [RemoteChange('review', 'other', 6)], 'e');
      expect(rows('remote_records').last['deleted'], 1);
    },
  );

  test('pulled records and opaque checkpoints commit or rollback together', () {
    sync.applyPull('private', [RemoteChange('visit', 'one', 1)], 'opaque:one');
    local.database.execute(
      "CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON pull_checkpoints BEGIN SELECT RAISE(ABORT,'interrupted'); END",
    );
    expect(
      () => sync.applyPull('private', [
        RemoteChange('visit', 'two', 2),
      ], 'opaque:two'),
      throwsA(isA<SqliteException>()),
    );
    expect(rows('remote_records').length, 1);
    expect(sync.checkpoint('private'), 'opaque:one');
    expect(() => sync.applyPull('catalogue', [], 'wrong'), throwsStateError);
    local.database.execute('DROP TRIGGER fail_checkpoint');
    sync.applyPull('private', [RemoteChange('visit', 'two', 2)], 'opaque:two');
    expect(sync.checkpoint('private'), 'opaque:two');
  });

  test(
    'public cache and checkpoints need no account and cannot contain private feed',
    () async {
      final public = LocalStore(
        sqlite3.openInMemory(),
        namespace: DataNamespace.publicCatalogue('test-environment'),
      );
      addTearDown(public.close);
      final cache = SyncStore(public);
      remote.pages['${public.namespace.key}:catalogue'] = PullPage([
        RemoteChange('bathroom', 'public', 1),
      ], 'public-checkpoint');
      auth.change(null);
      await SyncCoordinator(
        store: cache,
        auth: auth,
        remote: remote,
        now: () => now,
      ).refreshPublicCatalogue();
      expect(cache.checkpoint('catalogue'), 'public-checkpoint');
      expect(() => cache.checkpoint('private'), throwsStateError);
      expect(public.database.select('SELECT * FROM outbox'), isEmpty);
      expect(sync.checkpoint('private'), isNull);
    },
  );
  test(
    'acknowledgment revisions do not suppress equal-revision canonical pulls',
    () async {
      repository.createBathroom(bathroom());
      await coordinator.synchronize();
      final rev = sync.revision('bathroom', 'b')!;
      sync.applyPull('private', [
        RemoteChange('bathroom', 'b', rev, payload: {'name': 'Canonical'}),
      ], 'canonical');
      expect(
        jsonDecode(rows('remote_records').single['payload'] as String)['name'],
        'Canonical',
      );
      repository.updateBathroom(bathroom());
      expect(rows('outbox').last['base_revision'], rev);
    },
  );

  test(
    'pull response is discarded after logout, with checkpoint unchanged',
    () async {
      final gate = Completer<void>();
      remote.beforePull = () => gate.future;
      remote.pages['${scope.key}:private'] = PullPage([
        RemoteChange('review', 'private', 1),
      ], 'secret-page');
      final running = coordinator.synchronize();
      auth.change(null);
      gate.complete();
      await running;
      expect(rows('remote_records'), isEmpty);
      expect(sync.checkpoint('private'), isNull);
    },
  );

  test(
    'expiry during a request invalidates its result and retains original operation',
    () async {
      repository.createBathroom(bathroom());
      final gate = Completer<void>();
      remote.beforeSubmit = () => gate.future;
      auth.change(SessionIdentity(scope, now + 1));
      final running = coordinator.synchronize();
      now++;
      gate.complete();
      await running;
      expect(rows('outbox').single['state'], 'pending');
      expect(rows('server_revisions'), isEmpty);
      auth.change(SessionIdentity(scope, 100000));
      remote.beforeSubmit = null;
      await coordinator.synchronize();
      expect(remote.requests.first.id, remote.requests.last.id);
      expect(remote.applications, 1);
    },
  );

  test(
    'pull transport errors persist backoff; permanent validation waits for explicit retry',
    () async {
      remote.pullFailures.add(const RemoteFailure(RemoteFailureKind.transport));
      await coordinator.synchronize();
      expect(sync.checkpoint('private'), isNull);
      expect(rows('pull_status').single['next_attempt'], now + 1000);
      await coordinator.synchronize();
      expect(remote.pullRequests.length, 1);
      now += 1000;
      remote.pullFailures.add(
        const RemoteFailure(RemoteFailureKind.validation),
      );
      await coordinator.synchronize();
      now += 100000;
      await coordinator.synchronize();
      expect(remote.pullRequests.length, 2);
      expect(rows('pull_status').single['blocked'], 1);
      sync.retryPull('private');
      await coordinator.synchronize();
      expect(remote.pullRequests, [null, null, null]);
      expect(sync.checkpoint('private'), 'initial');
      expect(rows('pull_status'), isEmpty);
    },
  );

  test(
    'remote authentication failure pauses the same session generation',
    () async {
      repository.createBathroom(bathroom());
      remote.failures.add(
        const RemoteFailure(RemoteFailureKind.unavailableAuthentication),
      );
      await coordinator.synchronize();
      await coordinator.synchronize();
      expect(remote.requests.length, 1);
      auth.change(SessionIdentity(scope, 100000));
      await coordinator.synchronize();
      expect(rows('outbox').single['state'], 'acknowledged');
    },
  );

  test(
    'fake receipt rejects operation ID reuse with changed payload',
    () async {
      repository.createBathroom(bathroom());
      final op = sync.ready(now, 1).single;
      await remote.submit(auth.current!, op);
      final altered = Map<String, Object?>.of(rows('outbox').single)
        ..['payload'] = '{"different":true}';
      await expectLater(
        remote.submit(auth.current!, OutboxOperation.fromRow(altered, scope)),
        throwsA(
          isA<RemoteFailure>().having(
            (e) => e.kind,
            'kind',
            RemoteFailureKind.validation,
          ),
        ),
      );
      expect(remote.applications, 1);
    },
  );

  test(
    'removing an unclassified favourite never promotes it to uploadable',
    () {
      BathroomRepository(local).createBathroom(bathroom());
      local.database.execute(
        "INSERT INTO favourites VALUES(?,?,'unclassified_legacy')",
        [scope.subject, 'b'],
      );
      repository.setFavourite(scope.subject, 'b', false);
      expect(rows('favourites'), isEmpty);
      expect(rows('outbox'), isEmpty);
    },
  );

  test('deletion rollback retains visit, review and prior tombstone state', () {
    repository.createBathroom(bathroom());
    repository.saveReview(review(visit()), newVisit: visit(), isNew: true);
    local.database.execute(
      "CREATE TRIGGER fail_queue BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    expect(() => repository.deleteVisit('v'), throwsA(isA<SqliteException>()));
    expect(rows('reviews').length, 1);
    expect(rows('visits').length, 1);
    expect(rows('remote_records'), isEmpty);
  });
  test('foreign outbox responses cannot change another namespace', () {
    repository.createBathroom(bathroom());
    final foreign = LocalStore(
      sqlite3.openInMemory(),
      namespace: DataNamespace.account('other', 'subject-A'),
    );
    addTearDown(foreign.close);
    final other = SyncStore(foreign);
    final op = sync.ready(now, 1).single;
    expect(() => other.acknowledge(op, 1), throwsStateError);
    expect(() => other.reject(op, 'denied'), throwsStateError);
    expect(() => other.retry(op, now + 1, 'retry'), throwsStateError);
    expect(foreign.database.select('SELECT * FROM server_revisions'), isEmpty);
    expect(() => AppState.restore(local), throwsArgumentError);
  });

  test('coordinators sharing a session serialize access', () async {
    repository.createBathroom(bathroom());
    final gate = Completer<void>();
    remote.beforeSubmit = () => gate.future;
    final running = coordinator.synchronize();
    final other = SyncCoordinator(
      store: sync,
      auth: auth,
      remote: remote,
      now: () => now,
    );
    await other.synchronize();
    expect(remote.requests.length, 1);
    gate.complete();
    await running;
  });
  test(
    'remote deletion conflict, draft and checkpoints survive restart without resurrection',
    () async {
      local.close();
      final dir = Directory.systemTemp.createTempSync('conflict-restart');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/account.sqlite';
      local = LocalStore(sqlite3.open(path), namespace: scope);
      reconnect();
      repository.createBathroom(bathroom());
      await coordinator.synchronize();
      repository.saveReview(review(visit()), newVisit: visit(), isNew: true);
      final id = rows('outbox').last['operation_id'];
      remote.failures.add(
        RemoteFailure(
          RemoteFailureKind.conflict,
          conflict: RemoteChange('review', 'r', 9, deleted: true),
        ),
      );
      await coordinator.synchronize();
      sync.failPull('private', 'transport', now + 1000);
      local.close();
      local = LocalStore(sqlite3.open(path), namespace: scope);
      reconnect();
      expect(rows('outbox').last['operation_id'], id);
      expect(rows('outbox').last['state'], 'conflict');
      expect(rows('reviews').single['comment'], 'Draft');
      expect(rows('sync_conflicts').single['remote_deleted'], 1);
      expect(sync.checkpoint('private'), 'initial');
      expect(sync.pullAllowed('private', now), false);
      sync.applyPull('private', [
        RemoteChange(
          'review',
          'r',
          10,
          payload: {'comment': 'Stale resurrection'},
        ),
      ], 'next');
      expect(rows('remote_records').single['deleted'], 1);
      expect(rows('reviews').single['comment'], 'Draft');
    },
  );
}
