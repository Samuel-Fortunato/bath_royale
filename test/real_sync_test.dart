import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/provenance.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/tag_presentation.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/sync/private_sync_controller.dart';
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

class SwitchableRemote implements RemoteDataSource {
  final RemoteDataSource real;
  bool online = true;
  SwitchableRemote(this.real);
  @override
  Future<int> submit(SessionIdentity s, OutboxOperation op) {
    if (!online) throw const RemoteFailure(RemoteFailureKind.transport);
    return real.submit(s, op);
  }

  @override
  Future<PullPage> pull(
    DataNamespace n,
    String f,
    String? c,
    int l,
    SessionIdentity? s,
  ) {
    if (!online) throw const RemoteFailure(RemoteFailureKind.transport);
    return real.pull(n, f, c, l, s);
  }
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
        final result = await Process.run(
          'flutter',
          [
            'test',
            '--no-pub',
            'tool/sync_process_fixture.dart',
            '--reporter',
            'expanded',
          ],
          environment: {
            'BATH_SYNC_PROCESS_STEP': step,
            'BATH_SYNC_PROCESS_DB': database,
          },
        );
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
  test(
    'A2 real application controllers converge private account stores offline and after upgrade',
    () async {
      final account = config['privateA'] as Map;
      final subject = account['user']['id'] as String;
      final n = DataNamespace.account(scope.environment, subject);
      final tmp = Directory.systemTemp.createTempSync('a2-devices-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final path = '${tmp.path}/device-a.sqlite';
      var a = LocalStore(sqlite3.open(path), namespace: n);
      // Genuine A1 records existed before queueing/consent was available.
      var stateA = AppState.restoreAccountForTesting(BathroomRepository(a));
      final bathroom = stateA.createBathroom(
        'Trono privado entre dispositivos',
      );
      final v = Visit(
        id: uuid(),
        bathroomId: bathroom.id,
        userId: subject,
        visitedAt: DateTime.now().toUtc(),
      );
      final original = Review(
        id: uuid(),
        visitId: v.id,
        bathroomId: bathroom.id,
        authorId: subject,
        createdAt: v.visitedAt,
        rating: 4.2,
        paperAvailability: 2,
        hygiene: 3,
        comfort: 4,
        aesthetics: 0,
        comment: 'e\u0301' * 500,
        tags: [ReviewTagData(emoji: '👨‍' * 10 + '👨', label: 'e\u0301' * 30)],
      );
      stateA.saveReview(original, newVisit: v);
      stateA.toggleFavorite(bathroom.id);
      final previousRows = jsonEncode(
        a.database
            .select('SELECT * FROM reviews')
            .map((r) => Map.of(r))
            .toList(),
      );
      stateA.dispose();
      a.database.execute(
        'CREATE UNIQUE INDEX v6_name_uniqueness ON bathrooms(normalized_name); DROP TABLE sync_resolutions; DROP TABLE sync_preferences',
      );
      a.database.userVersion = 6;
      a.close();
      a = LocalStore(sqlite3.open(path), namespace: n);
      expect(
        jsonEncode(
          a.database
              .select('SELECT * FROM reviews')
              .map((r) => Map.of(r))
              .toList(),
        ),
        previousRows,
      );
      expect(a.database.userVersion, 7);
      final b = LocalStore(sqlite3.openInMemory(), namespace: n);
      final foreignN = DataNamespace.account(
        scope.environment,
        config['privateB']['user']['id'] as String,
      );
      final foreign = LocalStore(sqlite3.openInMemory(), namespace: foreignN);
      final authA = FakeAuthSession()..change(SessionIdentity(n, now + 600000));
      final authB = FakeAuthSession()..change(SessionIdentity(n, now + 600000));
      final authForeign = FakeAuthSession()
        ..change(SessionIdentity(foreignN, now + 600000));
      final http = HttpRemoteDataSource.forTesting(
        endpoint: Uri.parse(config['endpoint'] as String),
        environment: n.environment,
        accessToken: (s) => s.namespace == n
            ? account['access_token'] as String
            : config['privateB']['access_token'] as String,
      );
      final offline = SwitchableRemote(http);
      PrivateSyncController controller(
        LocalStore local,
        FakeAuthSession auth,
        RemoteDataSource remote,
      ) {
        final state = AppState.restoreAccountForTesting(
          BathroomRepository(
            local,
            syncContext: SyncWriteContext.account(local.namespace),
          ),
        );
        final c = PrivateSyncController(
          state: state,
          coordinator: SyncCoordinator(
            store: SyncStore(local),
            auth: auth,
            remote: remote,
            now: () => now,
            batchSize: 2,
            authorized: () => SyncStore(local).hasConsent,
          ),
          renew: () async {},
        );
        state.synchronization = c;
        return c;
      }

      var ca = controller(a, authA, offline);
      final cb = controller(b, authB, http);
      final cc = controller(foreign, authForeign, http);
      addTearDown(() {
        ca.state.dispose();
        cb.state.dispose();
        cc.state.dispose();
        a.close();
        b.close();
        foreign.close();
        http.close();
      });
      Future<void> settle(PrivateSyncController c) async {
        for (var i = 0; i < 30; i++) {
          await c.synchronize();
          if (!c.coordinator.moreWork) return;
        }
        fail('Bounded synchronization did not converge');
      }

      await ca.synchronize();
      expect(ca.store.hasConsent, false);
      expect(
        ca.store.pendingCount,
        0,
      ); // A1 rows are backfilled only on consent.
      await ca.enable();
      await settle(ca);
      expect(ca.error, isNull);
      expect(ca.store.pendingCount, 0);
      expect(ca.store.problems, isEmpty);
      await cb.enable();
      await settle(cb);
      expect(cb.state.allBathrooms.single.id, bathroom.id);
      expect(cb.state.visits.single.id, v.id);
      expect(cb.state.reviews.single.comment, original.comment);
      expect(cb.state.reviews.single.tags, original.tags);
      expect(cb.state.activityFor(bathroom.id).isFavorite, true);
      await cc.enable();
      await settle(cc);
      expect(cc.state.allBathrooms, isEmpty);
      expect(cc.state.visits, isEmpty);
      expect(cc.state.reviews, isEmpty);
      Review changed(Review r, String comment) => Review(
        id: r.id,
        visitId: r.visitId,
        bathroomId: r.bathroomId,
        authorId: r.authorId,
        createdAt: r.createdAt,
        updatedAt: DateTime.now().toUtc(),
        rating: r.rating,
        paperAvailability: r.paperAvailability,
        hygiene: r.hygiene,
        comfort: r.comfort,
        aesthetics: r.aesthetics,
        tags: r.tags,
        comment: comment,
      );
      offline.online = false;
      ca.state.saveReview(
        changed(ca.state.reviews.single, 'Alteração offline preservada'),
      );
      ca.state.toggleFavorite(bathroom.id);
      await ca.synchronize();
      expect(ca.error, contains('Sem ligação'));
      expect(ca.store.pendingCount, 2);
      cb.state.saveReview(
        changed(cb.state.reviews.single, 'Edição do outro dispositivo'),
      );
      await settle(cb);
      offline.online = true;
      await ca.retry();
      await settle(ca);
      expect(ca.store.problems.single['state'], 'conflict');
      expect(ca.state.reviews.single.comment, 'Alteração offline preservada');
      expect(ca.state.activityFor(bathroom.id).isFavorite, false);
      // Explicitly keep the local edit; it uses a new operation ID/CAS base.
      final failed = ca.store.problems.single['operation_id'] as String;
      ca.resend(failed);
      await settle(ca);
      await settle(cb);
      expect(ca.store.problems, isEmpty);
      expect(cb.state.reviews.single.comment, 'Alteração offline preservada');
      expect(cb.state.activityFor(bathroom.id).isFavorite, false);
      expect(ca.store.archives.single['operation_id'], failed);
      // A stale deletion must not erase a newly edited review on the other device.
      ca.state.deleteVisit(v.id, deleteReview: true);
      cb.state.saveReview(
        changed(cb.state.reviews.single, 'Edição antes da remoção'),
      );
      await settle(cb);
      await settle(ca);
      expect(ca.store.problems.single['state'], 'conflict');
      ca.useAccountVersion(ca.store.problems.single['operation_id'] as String);
      await settle(ca);
      expect(ca.state.reviews.single.comment, 'Edição antes da remoção');
      ca.state.deleteVisit(v.id, deleteReview: true);
      await settle(ca);
      await settle(cb);
      expect(cb.state.visits, isEmpty);
      expect(cb.state.reviews, isEmpty);
      // Local queue, consent, tombstones and archived edits survive restart.
      offline.online = false;
      ca.state.recordVisit(bathroom.id, visitedAt: DateTime.now().toUtc());
      ca.state.dispose();
      a.close();
      a = LocalStore(sqlite3.open(path), namespace: n);
      ca = controller(a, authA, offline);
      expect(ca.enabled, true);
      expect(ca.store.pendingCount, 1);
      expect(ca.store.archives, isNotEmpty);
      offline.online = true;
      await settle(ca);
      await settle(cb);
      expect(ca.store.pendingCount, 0);
      expect(cb.state.visits.single.id, ca.state.visits.single.id);
      expect(cb.state.reviews, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
