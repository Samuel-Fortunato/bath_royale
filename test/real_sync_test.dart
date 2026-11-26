import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/provenance.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/http_remote_data_source.dart';

late String catalogue;
String uuid() => const Uuid().v4();

/// Inject failures *after* an actual HTTP response, never a fake server outcome.
class ResponseGate implements RemoteDataSource {
  final RemoteDataSource real;
  Future<void> Function()? afterSubmit;
  bool lose = false;
  ResponseGate(this.real);
  @override
  Future<int> submit(SessionIdentity s, OutboxOperation op) async {
    final revision = await real.submit(s, op);
    await afterSubmit?.call();
    if (lose) {
      lose = false;
      throw const RemoteFailure(RemoteFailureKind.transport);
    }
    return revision;
  }

  @override
  Future<PullPage> pull(
    DataNamespace n,
    String f,
    String? c,
    int l,
    SessionIdentity? s,
  ) => real.pull(n, f, c, l, s);
}

void main() {
  final path = Platform.environment['BATH_SYNC_TEST_CONFIG'];
  if (path == null) {
    test(
      'real local synchronization requires explicit disposable context',
      () {},
      skip: 'Run POC_INSTANCE=sync backend/synchronization.py',
    );
    return;
  }
  final config =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  catalogue = config['catalogue'] as String;
  final scope = DataNamespace.account(
    config['environment'] as String,
    config['a']['user']['id'] as String,
  );
  late LocalStore local;
  late BathroomRepository repo;
  late SyncStore sync;
  late FakeAuthSession auth;
  late HttpRemoteDataSource transport;
  late ResponseGate gate;
  late SyncCoordinator coordinator;
  var now = DateTime.now().millisecondsSinceEpoch;
  var token = config['a']['access_token'] as String;
  SessionIdentity identity([DataNamespace? n]) =>
      SessionIdentity(n ?? scope, now + 60000);
  void connect() {
    repo = BathroomRepository(
      local,
      syncContext: SyncWriteContext.forTesting(scope),
    );
    sync = SyncStore(local);
    coordinator = SyncCoordinator(
      store: sync,
      auth: auth,
      remote: gate,
      now: () => now,
      jitter: () => 1,
      batchSize: 100,
    );
  }

  void seedCatalogue(LocalStore store) => store.insertBathroom(
    Bathroom(
      id: catalogue,
      name: 'Catálogo fictício',
      createdBy: scope.subject,
    ),
    provenance: Provenance.remote,
  );
  Visit visit() => Visit(
    id: uuid(),
    bathroomId: catalogue,
    userId: scope.subject,
    visitedAt: DateTime.now().toUtc(),
  );
  Review review(Visit v, {String? id, String comment = 'Rascunho fictício'}) =>
      Review(
        id: id ?? uuid(),
        visitId: v.id,
        bathroomId: v.bathroomId,
        authorId: scope.subject,
        createdAt: v.visitedAt,
        rating: 4.2,
        paperAvailability: 2,
        hygiene: 3,
        comfort: 4,
        aesthetics: 0,
        tags: ['Nice'],
        comment: comment,
      );
  List<Map<String, Object?>> rows(String table) => local.database
      .select('SELECT * FROM $table')
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  Future<void> acknowledged() async {
    await coordinator.synchronize();
    expect(rows('outbox').map((r) => r['state']), everyElement('acknowledged'));
  }

  Matcher failure(RemoteFailureKind kind) =>
      isA<RemoteFailure>().having((e) => e.kind, 'kind', kind);

  setUp(() {
    now = DateTime.now().millisecondsSinceEpoch;
    token = config['a']['access_token'] as String;
    local = LocalStore(sqlite3.openInMemory(), namespace: scope);
    seedCatalogue(local);
    auth = FakeAuthSession()..change(identity());
    transport = HttpRemoteDataSource.forTesting(
      endpoint: Uri.parse(config['endpoint'] as String),
      environment: scope.environment,
      accessToken: (s) =>
          s.namespace == scope ? token : config['b']['access_token'] as String,
    );
    gate = ResponseGate(transport);
    connect();
  });
  tearDown(() {
    local.close();
    transport.close();
  });

  test(
    'separate processes preserve offline operation and committed lost acknowledgment',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'real-sync-process-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = '${directory.path}/account.sqlite';
      for (final step in ['create', 'commitWithoutAck']) {
        final result = await Process.run('dart', [
          'run',
          'tool/sync_process_fixture.dart',
          step,
          database,
        ]);
        expect(
          result.exitCode,
          0,
          reason: 'Isolated Dart fixture must complete',
        );
      }
      local.close();
      local = LocalStore(sqlite3.open(database), namespace: scope);
      connect();
      final before = rows('outbox').single;
      expect(before['state'], 'pending');
      await acknowledged();
      expect(rows('outbox').single['operation_id'], before['operation_id']);
      expect(rows('bathrooms').length, 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'offline compound, queued edit and deletion have complete shared revisions',
    () async {
      final v = visit();
      final r = review(v);
      repo.saveReview(r, newVisit: v, isNew: true);
      repo.saveReview(
        review(v, id: r.id, comment: 'Edição em fila'),
        isNew: false,
      );
      expect(rows('outbox').last['base_revision'], isNull);
      await acknowledged();
      expect(sync.revision('visit', v.id), sync.revision('review', r.id));
      final revision = sync.revision('review', r.id)!;
      repo.deleteVisit(v.id);
      await acknowledged();
      expect(sync.revision('visit', v.id), greaterThan(revision));
      expect(sync.revision('visit', v.id), sync.revision('review', r.id));
      expect(rows('visits'), isEmpty);
      expect(rows('reviews'), isEmpty);
    },
  );

  test(
    'visit then review creation and explicit favourite booleans retry safely',
    () async {
      final v = visit();
      repo.recordVisit(v);
      repo.saveReview(review(v), isNew: true);
      repo.setFavourite(scope.subject, catalogue, true);
      repo.setFavourite(scope.subject, catalogue, false);
      await acknowledged();
      expect(rows('outbox').length, 4);
      repo.setFavourite(scope.subject, catalogue, true);
      gate.lose = true;
      await coordinator.synchronize();
      expect(rows('outbox').last['state'], 'pending');
      now += 1000;
      await acknowledged();
      expect(rows('favourites').length, 1);
    },
  );

  test(
    'two device edits conflict and retain local drafts; delete prevents resurrection',
    () async {
      final v = visit();
      final r = review(v);
      repo.saveReview(r, newVisit: v, isNew: true);
      await acknowledged();
      final other = LocalStore(sqlite3.openInMemory(), namespace: scope);
      addTearDown(other.close);
      seedCatalogue(other);
      final otherRepo = BathroomRepository(other);
      otherRepo.saveReview(r, newVisit: v, isNew: true);
      final device = BathroomRepository(
        other,
        syncContext: SyncWriteContext.forTesting(scope),
      );
      final otherSync = SyncStore(other);
      otherSync.applyPull('private', [
        RemoteChange('review', r.id, sync.revision('review', r.id)!),
        RemoteChange('visit', v.id, sync.revision('visit', v.id)!),
      ], uuid());
      device.saveReview(
        review(v, id: r.id, comment: 'Segundo dispositivo'),
        isNew: false,
      );
      repo.saveReview(
        review(v, id: r.id, comment: 'Primeiro dispositivo'),
        isNew: false,
      );
      await acknowledged();
      final otherAuth = FakeAuthSession()..change(identity());
      final otherCoordinator = SyncCoordinator(
        store: otherSync,
        auth: otherAuth,
        remote: transport,
        now: () => now,
        batchSize: 100,
      );
      await otherCoordinator.synchronize();
      expect(
        other.database.select('SELECT state FROM outbox').single['state'],
        'conflict',
      );
      expect(
        other.database.select('SELECT comment FROM reviews').single['comment'],
        'Segundo dispositivo',
      );
      // Queue a stale deletion and race it against another device's review edit.
      final staleVisit = sync.revision('visit', v.id)!;
      repo.saveReview(
        review(v, id: r.id, comment: 'Nova edição'),
        isNew: false,
      );
      await acknowledged();
      final delete = OutboxOperation.fromRow({
        'operation_id': uuid(),
        'entity_type': 'visit',
        'entity_id': v.id,
        'operation_type': 'deleteVisit',
        'payload': jsonEncode({'id': v.id, 'deletedReviewId': r.id}),
        'base_revision': staleVisit,
        'attempts': 0,
      }, scope);
      await expectLater(
        transport.submit(identity(), delete),
        throwsA(failure(RemoteFailureKind.conflict)),
      );
      final staleEdit = otherSync.ready(now, 1);
      expect(staleEdit, isEmpty);
      repo.deleteVisit(v.id);
      await acknowledged();
      final staleRow = Map<String, Object?>.from(
        other.database.select('SELECT * FROM outbox').single,
      )..['operation_id'] = uuid();
      await expectLater(
        transport.submit(identity(), OutboxOperation.fromRow(staleRow, scope)),
        throwsA(
          isA<RemoteFailure>().having(
            (e) => e.conflict?.deleted,
            'deleted before stale edit',
            true,
          ),
        ),
      );
      final resurrect = OutboxOperation.fromRow({
        'operation_id': uuid(),
        'entity_type': 'review',
        'entity_id': r.id,
        'operation_type': 'createVisitReview',
        'payload': jsonEncode({
          'visit': {
            'id': v.id,
            'bathroom': catalogue,
            'user': scope.subject,
            'at': v.visitedAt.microsecondsSinceEpoch,
          },
          'review': {},
        }),
        'base_revision': null,
        'attempts': 0,
      }, scope);
      await expectLater(
        transport.submit(identity(), resurrect),
        throwsA(
          isA<RemoteFailure>().having(
            (e) => e.conflict?.deleted,
            'tombstone',
            true,
          ),
        ),
      );
    },
  );

  test(
    'real commit response invalidated by account switch; expiry and environment fail closed',
    () async {
      repo.createBathroom(
        Bathroom(
          id: uuid(),
          name: 'Proposta fictícia',
          createdBy: scope.subject,
        ),
      );
      gate.afterSubmit = () async {
        auth.change(
          identity(
            DataNamespace.account(
              scope.environment,
              config['b']['user']['id'] as String,
            ),
          ),
        );
      };
      await coordinator.synchronize();
      expect(rows('outbox').single['state'], 'pending');
      expect(rows('pull_checkpoints'), isEmpty);
      gate.afterSubmit = null;
      auth.change(identity());
      await acknowledged();
      repo.createBathroom(
        Bathroom(id: uuid(), name: 'Sessão expirada', createdBy: scope.subject),
      );
      token = config['expired'] as String;
      await coordinator.synchronize();
      expect(rows('outbox').last['state'], 'pending');
      token = config['a']['access_token'] as String;
      auth.change(identity());
      await acknowledged();
      token = config['b']['access_token'] as String;
      await expectLater(
        transport.pull(scope, 'private', null, 1, identity()),
        throwsA(failure(RemoteFailureKind.authorization)),
      );
      token = config['a']['access_token'] as String;
      final wrong = DataNamespace.account(
        'different-installation',
        scope.subject,
      );
      await expectLater(
        transport.pull(wrong, 'private', null, 1, identity(wrong)),
        throwsA(failure(RemoteFailureKind.authorization)),
      );
      await expectLater(
        transport.pull(scope, 'catalogue', null, 1, identity()),
        throwsA(failure(RemoteFailureKind.authorization)),
      );
    },
  );

  test(
    'real pull and checkpoint rollback together; full replay preserves pending drafts',
    () async {
      repo.createBathroom(
        Bathroom(
          id: uuid(),
          name: 'Rascunho pendente',
          createdBy: scope.subject,
        ),
      );
      final page = await transport.pull(
        scope,
        'private',
        null,
        100,
        identity(),
      );
      local.database.execute(
        "CREATE TRIGGER fail_page BEFORE INSERT ON pull_checkpoints BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      expect(
        () => sync.applyPull('private', page.changes, page.checkpoint),
        throwsA(isA<SqliteException>()),
      );
      expect(rows('remote_records'), isEmpty);
      expect(sync.checkpoint('private'), isNull);
      expect(rows('server_revisions'), isEmpty);
      local.database.execute('DROP TRIGGER fail_page');
      sync.applyPull('private', page.changes, page.checkpoint);
      sync.applyPull('private', page.changes, page.checkpoint);
      expect(rows('bathrooms').last['name'], 'Rascunho pendente');
      expect(rows('outbox').single['state'], 'pending');
      final public = await transport.pull(
        DataNamespace.publicCatalogue(scope.environment),
        'catalogue',
        null,
        100,
        null,
      );
      expect(
        public.changes.map((c) => c.entityType),
        everyElement(anyOf('bathroom', 'review')),
      );
      expect(
        public.changes.every((c) => !c.payload.containsKey('visit_id')),
        true,
      );
    },
  );

  test(
    'demo and unclassified local records never enter actual upload path',
    () async {
      for (final origin in [Provenance.demo, Provenance.unclassifiedLegacy]) {
        final b = Bathroom(
          id: uuid(),
          name: origin.value,
          createdBy: scope.subject,
        );
        local.insertBathroom(b, provenance: origin);
        repo.recordVisit(
          Visit(
            id: uuid(),
            bathroomId: b.id,
            userId: scope.subject,
            visitedAt: DateTime.now(),
          ),
        );
        repo.setFavourite(scope.subject, b.id, true);
      }
      await coordinator.synchronize();
      expect(rows('outbox'), isEmpty);
    },
  );
}
