import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/provenance.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/account_projection.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/private_sync_controller.dart';

void main() {
  final namespace = DataNamespace.account('private-test', 'alice');
  late LocalStore local;
  late AppState state;
  late SyncStore store;
  late FakeRemoteDataSource remote;
  late FakeAuthSession auth;
  late PrivateSyncController controller;
  setUp(() {
    local = LocalStore(sqlite3.openInMemory(), namespace: namespace);
    store = SyncStore(local);
    state = AppState.restoreAccountForTesting(
      BathroomRepository(
        local,
        syncContext: SyncWriteContext.account(namespace),
      ),
    );
    auth = FakeAuthSession()..change(SessionIdentity(namespace, 1000000));
    remote = FakeRemoteDataSource();
    controller = PrivateSyncController(
      state: state,
      coordinator: SyncCoordinator(
        store: store,
        auth: auth,
        remote: remote,
        now: () => 1000,
        authorized: () => store.hasConsent,
      ),
      renew: () async {},
    );
    state.synchronization = controller;
  });
  tearDown(() {
    state.dispose();
    local.close();
  });

  test('identity and durable queue never grant first-upload consent', () async {
    state.createBathroom('Só local');
    expect(store.pendingCount, 1);
    await controller.synchronize();
    await controller.coordinator.synchronize();
    expect(remote.requests, isEmpty);
    expect(remote.pullRequests, isEmpty);
    await controller.enable();
    expect(remote.requests.length, 1);
    expect(store.pendingCount, 0);
    expect(store.hasConsent, true);
  });
  test(
    'consent backfills only genuine account rows and rolls back atomically',
    () async {
      final plain = AppState.restoreAccountForTesting(
        BathroomRepository(local),
      );
      final genuine = plain.createBathroom('Antes de A2');
      plain.recordVisit(genuine.id, visitedAt: DateTime.utc(2030));
      plain.toggleFavorite(genuine.id);
      plain.dispose();
      for (final origin in [Provenance.demo, Provenance.unclassifiedLegacy]) {
        local.insertBathroom(
          Bathroom(
            id: origin.value,
            name: origin.value,
            createdBy: namespace.subject,
          ),
          provenance: origin,
        );
      }
      local.database.execute(
        "CREATE TRIGGER fail_consent BEFORE INSERT ON sync_preferences BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      expect(store.consent, throwsA(isA<SqliteException>()));
      expect(store.hasConsent, false);
      expect(store.pendingCount, 0);
      local.database.execute('DROP TRIGGER fail_consent');
      await controller.enable();
      expect(remote.requests.length, 3);
      expect(
        remote.requests.every(
          (r) =>
              !r.payload.contains('demo') &&
              !r.payload.contains('unclassified_legacy'),
        ),
        true,
      );
    },
  );
  test(
    'backgrounding cancels continuation and retains durable operation identity',
    () async {
      state.createBathroom('Primeiro');
      state.createBathroom('Segundo');
      final entered = Completer<void>(), released = Completer<void>();
      remote.beforeSubmit = () async {
        if (!entered.isCompleted) entered.complete();
        await released.future;
      };
      final run = controller.enable();
      await entered.future;
      final original = store.ready(1000, 1).single.id;
      controller.foreground(false);
      released.complete();
      await run;
      expect(remote.requests.length, 1);
      expect(store.pendingCount, 2);
      expect(store.ready(1000, 1).single.id, original);
      remote.beforeSubmit = null;
      controller.foreground(true);
      await controller.synchronize();
      expect(remote.applications, 2);
      expect(store.pendingCount, 0);
    },
  );
  test(
    'unseen remote revisions cannot become the base of queued local edits',
    () {
      final b = state.createBathroom('Primeiro');
      store.applyPull('private', [
        RemoteChange('bathroom', b.id, 9, payload: {'name': 'Unseen'}),
      ], 'cursor');
      state.updateBathroom(
        Bathroom(
          id: b.id,
          name: 'Segundo',
          createdBy: b.createdBy,
          emoji: b.emoji,
          accent: b.accent,
        ),
      );
      final rows = local.database.select(
        'SELECT base_revision FROM outbox ORDER BY sequence',
      );
      expect(rows.map((r) => r['base_revision']), [null, null]);
    },
  );
  test(
    'recovery archives the exact rejected branch without releasing its dependent upload',
    () async {
      final b = state.createBathroom('Original');
      state.updateBathroom(
        Bathroom(
          id: b.id,
          name: 'Edited',
          createdBy: b.createdBy,
          emoji: b.emoji,
          accent: b.accent,
        ),
      );
      remote.failures.add(const RemoteFailure(RemoteFailureKind.validation));
      await controller.enable();
      expect(store.problems.length, 1);
      expect(store.pendingCount, 1);
      final original = store.problems.single['payload'];
      controller.useAccountVersion(
        store.problems.single['operation_id'] as String,
      );
      await controller.synchronize();
      expect(store.problems, isEmpty);
      expect(store.pendingCount, 0);
      expect(store.archives.length, 2);
      expect(store.archives.first['payload'], original);
      expect(remote.requests.length, 1);
      expect(
        state.allBathrooms.single.name,
        'Edited',
      ); // no remote version exists
    },
  );
  test(
    'retrying a conflict uses the displayed revision and preserves the original payload',
    () async {
      final b = state.createBathroom('Preservado');
      remote.failures.add(
        RemoteFailure(
          RemoteFailureKind.conflict,
          conflict: RemoteChange(
            'bathroom',
            b.id,
            4,
            payload: {'name': 'Conta'},
          ),
        ),
      );
      await controller.enable();
      final row = store.problems.single;
      store.applyPull('private', [
        RemoteChange('bathroom', b.id, 8, payload: {'name': 'New unseen'}),
      ], 'c');
      store.retryProblem(row['operation_id'] as String);
      final retry = store.ready(1000, 1).single;
      expect(retry.baseRevision, 4);
      expect(retry.id, isNot(row['operation_id']));
      expect(retry.payload, row['payload']);
      expect(store.archives.single['payload'], row['payload']);
    },
  );
  test(
    'consent, pending payloads and account records survive close and restart',
    () {
      final directory = Directory.systemTemp.createTempSync('a2-restart');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/account.sqlite';
      var db = LocalStore(sqlite3.open(path), namespace: namespace);
      var repo = BathroomRepository(
        db,
        syncContext: SyncWriteContext.account(namespace),
      );
      repo.createBathroom(
        Bathroom(id: 'one', name: 'Restauro', createdBy: namespace.subject),
      );
      SyncStore(db).consent();
      final before = jsonEncode(
        db.database
            .select('SELECT * FROM outbox')
            .map((r) => Map.of(r))
            .toList(),
      );
      db.close();
      db = LocalStore(sqlite3.open(path), namespace: namespace);
      expect(SyncStore(db).hasConsent, true);
      expect(
        jsonEncode(
          db.database
              .select('SELECT * FROM outbox')
              .map((r) => Map.of(r))
              .toList(),
        ),
        before,
      );
      expect(db.load()!.bathrooms.single.name, 'Restauro');
      db.close();
    },
  );
  test(
    'a rejected-session response renews once and retries only after identity renewal',
    () async {
      state.createBathroom('Sessão renovada');
      remote.failures.add(
        const RemoteFailure(RemoteFailureKind.unavailableAuthentication),
      );
      controller.dispose();
      var renewals = 0;
      controller = PrivateSyncController(
        state: state,
        coordinator: SyncCoordinator(
          store: store,
          auth: auth,
          remote: remote,
          now: () => 1000,
          authorized: () => store.hasConsent,
        ),
        renew: () async {},
        refreshSession: () async {
          renewals++;
          auth.change(SessionIdentity(namespace, 2000000));
          return true;
        },
      );
      state.synchronization = controller;
      await controller.enable();
      expect(renewals, 1);
      expect(store.pendingCount, 1);
      await controller.synchronize();
      expect(store.pendingCount, 0);
      expect(remote.applications, 1);
    },
  );
  test(
    'corrected rejected text uses a new operation and retains the complete original',
    () async {
      state.createBathroom('Original com acentos e\u0301');
      remote.failures.add(const RemoteFailure(RemoteFailureKind.validation));
      await controller.enable();
      final original = store.problems.single;
      expect(
        () => controller.resend(
          original['operation_id'] as String,
          correctedText: 'a' * 101,
        ),
        throwsArgumentError,
      );
      expect(store.problems.length, 1);
      expect(store.archives, isEmpty);
      controller.resend(
        original['operation_id'] as String,
        correctedText: 'Correção e\u0301',
      );
      expect(state.allBathrooms.single.name, 'Correção e\u0301');
      expect(store.archives.single['payload'], original['payload']);
      await controller.synchronize();
      expect(store.pendingCount, 0);
      expect(remote.requests.last.payload, contains('Correção e\u0301'));
    },
  );
  test(
    'full private replay keeps local edits, archived input and consent',
    () async {
      final b = state.createBathroom('Pendente');
      store.consent();
      store.applyPull('private', [
        RemoteChange('bathroom', b.id, 1, payload: {'name': 'Remote'}),
      ], 'unknown-cursor');
      final payload = store.ready(1000, 1).single.payload;
      store.resetPrivateCheckpoint();
      expect(store.checkpoint('private'), isNull);
      expect(store.ready(1000, 1).single.payload, payload);
      expect(store.hasConsent, true);
      expect(local.database.select('SELECT * FROM remote_records').length, 1);
    },
  );
  test(
    'historical pages cannot replace acknowledged edits and terminal conflicts remain recoverable',
    () {
      final b = state.createBathroom('Alteração confirmada');
      final op = store.ready(1000, 1).single;
      store.acknowledge(op, 10);
      Map<String, Object?> payload(String name) => {
        'id': b.id,
        'name': name,
        'contributor_id': namespace.subject,
        'emoji': b.emoji,
        'accent': b.accent,
      };
      store.applyPull('private', [
        RemoteChange('bathroom', b.id, 4, payload: payload('Página antiga')),
      ], 'old');
      AccountProjection(store).apply();
      state.reloadAccountData();
      expect(state.allBathrooms.single.name, 'Alteração confirmada');
      store.applyPull('private', [
        RemoteChange('bathroom', b.id, 10, payload: payload('Conta atual')),
      ], 'current');
      AccountProjection(store).apply();
      state.reloadAccountData();
      expect(state.allBathrooms.single.name, 'Conta atual');
      state.updateBathroom(
        Bathroom(
          id: b.id,
          name: 'Edição offline',
          createdBy: b.createdBy,
          emoji: b.emoji,
          accent: b.accent,
        ),
      );
      final edit = store.ready(1000, 1).single;
      store.reject(
        edit,
        'conflict',
        conflict: RemoteChange('bathroom', b.id, 11, deleted: true),
      );
      store.useAccountVersion(edit.id);
      AccountProjection(store).apply();
      state.reloadAccountData();
      expect(state.allBathrooms, isEmpty);
      expect(store.archives.single['payload'], edit.payload);
      final parent = state.createBathroom('Favorito offline');
      store.acknowledge(store.ready(1000, 1).single, 20);
      state.toggleFavorite(parent.id);
      final favourite = store.ready(1000, 1).single;
      store.applyPull('private', [
        RemoteChange('bathroom', parent.id, 21, deleted: true),
      ], 'removed-parent');
      AccountProjection(store).apply();
      state.reloadAccountData();
      expect(state.allBathrooms.single.id, parent.id);
      expect(state.activityFor(parent.id).isFavorite, true);
      store.reject(favourite, 'authorization');
      store.useAccountVersion(favourite.id);
      AccountProjection(store).apply();
      state.reloadAccountData();
      expect(state.allBathrooms, isEmpty);
    },
  );
  test(
    'a pull arriving during an editor cannot advance its unseen conflict base',
    () async {
      final b = state.createBathroom('Base visível');
      final entered = Completer<void>(), released = Completer<void>();
      remote.pages['${namespace.key}:private'] = PullPage([
        RemoteChange(
          'bathroom',
          b.id,
          5,
          payload: {'name': 'Outro dispositivo'},
        ),
      ], 'new');
      remote.beforePull = () async {
        entered.complete();
        await released.future;
      };
      final run = controller.enable();
      await entered.future;
      final close = state.retainDraft();
      released.complete();
      await run;
      expect(store.checkpoint('private'), isNull);
      expect(local.database.select('SELECT * FROM remote_records'), isEmpty);
      expect(store.revision('bathroom', b.id), 1);
      state.updateBathroom(
        Bathroom(
          id: b.id,
          name: 'Edição a partir da base visível',
          createdBy: b.createdBy,
          emoji: b.emoji,
          accent: b.accent,
        ),
      );
      expect(store.ready(1000, 1).single.baseRevision, 1);
      close();
    },
  );
  test(
    'offline expired authentication cannot turn ready outbox rows into rapid retries',
    () async {
      state.createBathroom('Offline');
      auth.change(SessionIdentity(namespace, 500));
      controller.dispose();
      var renewals = 0;
      controller = PrivateSyncController(
        state: state,
        coordinator: SyncCoordinator(
          store: store,
          auth: auth,
          remote: remote,
          now: () => 1000,
          authorized: () => store.hasConsent,
        ),
        renew: () async {
          renewals++;
        },
      );
      state.synchronization = controller;
      await controller.enable();
      expect(renewals, 1);
      expect(store.pendingCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(renewals, 1);
      expect(remote.requests, isEmpty);
      expect(controller.error, contains('sessão expirada'));
    },
  );
}
