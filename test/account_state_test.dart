import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/state/account_state_scope.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';

void main() {
  test(
    'device scope hides retained guest draft when authentication overtakes editing',
    () async {
      final auth = FakeAuthSession();
      final scope = AccountStateScope.device(
        auth: auth,
        openStore: (n) async =>
            LocalStore(sqlite3.openInMemory(), namespace: n),
      );
      await scope.select(const DataNamespace.guest());
      final release = scope.state!.retainDraft();
      auth.change(
        SessionIdentity(
          DataNamespace.account('environment', 'subject'),
          DateTime.now().millisecondsSinceEpoch + 60000,
        ),
      );
      expect(scope.isAccessible, isFalse);
      await expectLater(
        scope.select(auth.current!.namespace),
        throwsStateError,
      );
      auth.logout();
      expect(scope.isAccessible, isTrue);
      release();
      scope.dispose();
      auth.dispose();
    },
  );

  late Directory directory;
  late FakeAuthSession auth;
  late AccountStateScope scope;
  var now = 1000;
  final a = DataNamespace.account('test-backend', 'subject-A');
  final b = DataNamespace.account('test-backend', 'subject-B');
  final otherEnvironment = DataNamespace.account('other-backend', 'subject-A');
  const guest = DataNamespace.guest();
  LocalStore open(DataNamespace namespace) => LocalStore(
    sqlite3.open('${directory.path}/${namespace.fileName}'),
    namespace: namespace,
  );
  SessionIdentity identity(DataNamespace namespace) =>
      SessionIdentity(namespace, now + 60000);
  Future<void> select(DataNamespace namespace, {bool queue = false}) async {
    auth.change(namespace.isAccount ? identity(namespace) : null);
    await scope.select(
      namespace,
      synchronizationForTesting: queue
          ? SyncWriteContext.forTesting(namespace)
          : null,
    );
  }

  setUp(() {
    now = 1000;
    directory = Directory.systemTemp.createTempSync('bath-account-test-');
    auth = FakeAuthSession(now: () => now);
    scope = AccountStateScope.forTesting(
      auth: auth,
      openStore: (namespace) async => open(namespace),
      now: () => now,
    );
  });
  tearDown(() {
    scope.dispose();
    auth.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'guest initialization needs no authentication or account store',
    () async {
      await scope.select(guest);
      expect(auth.current, isNull);
      expect(scope.isAccessible, isTrue);
      expect(scope.state!.allBathrooms, hasLength(6));
      expect(scope.state!.visits, hasLength(6));
      expect(directory.listSync().whereType<File>(), hasLength(1));
      expect(scope.state!.repository!.store.namespace, guest);
      expect(
        SyncStore(scope.state!.repository!.store).ready(now, 100),
        isEmpty,
      );
    },
  );

  test(
    'fresh account is empty and authentication grants no transfer',
    () async {
      await scope.select(guest);
      final guestState = scope.state!;
      guestState.createBathroom('Trono privado de convidado');
      final guestData = guestState.localData;
      auth.change(identity(a));
      expect(scope.state, same(guestState)); // Identity alone does not select.
      expect(directory.listSync().whereType<File>(), hasLength(1));
      await scope.select(a);
      final state = scope.state!;
      expect(state.currentUserId, a.subject);
      expect(state.allBathrooms, isEmpty);
      expect(state.visits, isEmpty);
      expect(state.reviews, isEmpty);
      expect(state.localData.favourites, isEmpty);
      final bathroom = state.createBathroom('Trono privado A');
      state.recordVisit(bathroom.id, visitedAt: DateTime.utc(2026));
      state.toggleFavorite(bathroom.id);
      state.toggleTheme();
      final store = state.repository!.store;
      expect(store.database.select('SELECT * FROM outbox'), isEmpty);
      expect(store.database.select('SELECT * FROM remote_records'), isEmpty);
      expect(store.database.select('SELECT * FROM pull_checkpoints'), isEmpty);
      expect(store.bathroomProvenance(bathroom.id).value, 'user_created');
      await select(guest);
      expect(
        scope.state!.allBathrooms.map((b) => b.id),
        guestData.bathrooms.map((b) => b.id),
      );
      expect(scope.state!.visits.length, guestData.visits.length);
      expect(scope.state!.reviews.length, guestData.reviews.length);
      expect(
        scope.state!.localData.favourites.length,
        guestData.favourites.length,
      );
    },
  );

  test(
    'A/B and backend environments isolate domain data and settings',
    () async {
      await select(a);
      final bathroom = scope.state!.createBathroom('Só A');
      scope.state!.recordVisit(bathroom.id, visitedAt: DateTime.utc(2026));
      scope.state!.toggleFavorite(bathroom.id);
      scope.state!.toggleTheme();
      await select(b);
      expect(scope.state!.allBathrooms, isEmpty);
      expect(scope.state!.visits, isEmpty);
      expect(scope.state!.darkMode, isTrue);
      scope.state!.createBathroom('Só B');
      await select(otherEnvironment);
      expect(scope.state!.allBathrooms, isEmpty);
      expect(scope.state!.currentUserId, a.subject);
      scope.state!.createBathroom('Só noutro ambiente');
      await select(a);
      expect(scope.state!.allBathrooms.single.id, bathroom.id);
      expect(scope.state!.visits, hasLength(1));
      expect(scope.state!.localData.favourites.single.isFavorite, isTrue);
      expect(scope.state!.darkMode, isFalse);
      await select(b);
      expect(scope.state!.allBathrooms.single.name, 'Só B');
    },
  );

  test(
    'committed pending operations survive logout, selection and restart',
    () async {
      await select(a, queue: true);
      final bathroom = scope.state!.createBathroom('Pendente A');
      final original = SyncStore(
        scope.state!.repository!.store,
      ).ready(now, 1).single;
      auth.logout();
      expect(scope.isAccessible, isFalse);
      await scope.select(guest);
      expect(
        scope.state!.allBathrooms.any((b) => b.id == bathroom.id),
        isFalse,
      );
      await select(b);
      expect(SyncStore(scope.state!.repository!.store).ready(now, 10), isEmpty);
      scope.dispose();
      scope = AccountStateScope.forTesting(
        auth: auth,
        openStore: (namespace) async => open(namespace),
        now: () => now,
      );
      await select(a); // Authentication does not opt in to further queueing.
      final restored = SyncStore(
        scope.state!.repository!.store,
      ).ready(now, 1).single;
      expect(restored.id, original.id);
      expect(restored.payload, original.payload);
      expect(scope.state!.allBathrooms.single.id, bathroom.id);
      scope.state!.createBathroom('Local sem consentimento');
      expect(
        SyncStore(scope.state!.repository!.store).ready(now, 10),
        hasLength(1),
      );
    },
  );

  test(
    'renewal, expiry and invalidation retain local state without reseeding',
    () async {
      await select(a);
      final state = scope.state!;
      state.createBathroom('Persiste');
      final generation = auth.generation;
      expect(
        await auth.renew((_) async => SessionIdentity(a, now + 100000)),
        isTrue,
      );
      expect(auth.generation, generation + 1);
      expect(auth.status, SessionStatus.authenticated);
      expect(scope.state, same(state));
      now += 100000;
      expect(auth.status, SessionStatus.expired);
      expect(
        scope.isAccessible,
        isFalse,
      ); // Checks clock even before notification.
      auth.checkExpiry();
      final expiredGeneration = auth.generation;
      auth.checkExpiry();
      expect(auth.generation, expiredGeneration);
      expect(await auth.renew((_) async => identity(a)), isTrue);
      expect(scope.isAccessible, isTrue);
      expect(scope.state, same(state));
      auth.invalidate();
      expect(auth.status, SessionStatus.invalidated);
      expect(auth.current, isNull);
      expect(scope.isAccessible, isFalse);
      auth.change(identity(a));
      expect(scope.state!.allBathrooms.single.name, 'Persiste');
    },
  );

  test(
    'delayed renewal cannot undo logout, invalidation or account switches',
    () async {
      for (final event in ['logout', 'invalidate', 'switch', 'renew']) {
        auth.change(identity(a));
        final response = Completer<SessionIdentity>();
        final renewal = auth.renew((_) => response.future);
        switch (event) {
          case 'logout':
            auth.logout();
          case 'invalidate':
            auth.invalidate();
          case 'switch':
            auth.change(identity(b));
          case 'renew':
            auth.change(identity(a));
        }
        final generation = auth.generation;
        final current = auth.current;
        response.complete(identity(a));
        expect(await renewal, isFalse);
        expect(auth.generation, generation);
        expect(auth.current, same(current));
      }
    },
  );

  test('renewal rejects foreign, expired and non-account identities', () async {
    auth.change(identity(a));
    await expectLater(auth.renew((_) async => identity(b)), throwsStateError);
    await expectLater(
      auth.renew((_) async => SessionIdentity(a, now)),
      throwsStateError,
    );
    expect(
      () => auth.change(const SessionIdentity(guest, 100000)),
      throwsArgumentError,
    );
    expect(auth.current!.namespace, a);
  });

  test(
    'open editors block switching, logout selection and scope disposal',
    () async {
      await select(a);
      final state = scope.state!;
      final release = state.retainDraft();
      auth.change(identity(b));
      expect(scope.isAccessible, isFalse);
      await expectLater(scope.select(b), throwsStateError);
      auth.logout();
      await expectLater(scope.select(guest), throwsStateError);
      expect(scope.dispose, throwsStateError);
      expect(scope.state, same(state));
      release();
      release();
      expect(state.hasUncommittedWork, isFalse);
      await scope.select(guest);
    },
  );

  test(
    'failed commit retains exact payload and completion until explicit retry',
    () async {
      await select(a, queue: true);
      final state = scope.state!;
      final store = state.repository!.store;
      store.database.execute(
        "CREATE TRIGGER fail_queue BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      final bathroom = state.createBathroom('Guardar antes de mudar');
      final completion = state.persistenceComplete;
      var completed = false;
      completion.then((_) => completed = true);
      expect(state.storageError, isA<SqliteException>());
      expect(state.allBathrooms, isEmpty);
      expect(store.database.select('SELECT * FROM bathrooms'), isEmpty);
      auth.logout();
      await expectLater(scope.select(guest), throwsStateError);
      await Future<void>.value();
      expect(completed, isFalse);
      store.database.execute('DROP TRIGGER fail_queue');
      state.retryStorage();
      await completion;
      expect(state.allBathrooms.single.id, bathroom.id);
      expect(SyncStore(store).ready(now, 1).single.entityId, bathroom.id);
      await scope.select(guest);
      await select(a);
      expect(scope.state!.allBathrooms.single.id, bathroom.id);
    },
  );

  test(
    'replacement disposes old state and stops old listeners and writes',
    () async {
      await select(a);
      final old = scope.state!;
      final store = old.repository!.store;
      var notices = 0;
      old.addListener(() => notices++);
      await select(b);
      expect(store.isClosed, isTrue);
      expect(() => old.createBathroom('Obsoleto'), throwsStateError);
      expect(old.retryStorage, throwsStateError);
      expect(old.retainDraft, throwsStateError);
      scope.state!.createBathroom('Novo B');
      expect(notices, 0);
    },
  );

  test(
    'late store opens cannot replace a newer selection or logged-out session',
    () async {
      scope.dispose();
      final gate = Completer<LocalStore>();
      scope = AccountStateScope.forTesting(
        auth: auth,
        openStore: (namespace) =>
            namespace == a ? gate.future : Future.value(open(namespace)),
        now: () => now,
      );
      auth.change(identity(a));
      final opening = scope.select(a);
      await select(b);
      final staleStore = open(a);
      gate.complete(staleStore);
      expect(await opening, isFalse);
      expect(staleStore.isClosed, isTrue);
      expect(scope.state!.currentUserId, b.subject);
    },
  );

  test(
    'draft opened during store initialization prevents replacement',
    () async {
      await select(guest);
      final old = scope.state!;
      scope.dispose();
      final gate = Completer<LocalStore>();
      scope = AccountStateScope.forTesting(
        auth: auth,
        openStore: (namespace) =>
            namespace == a ? gate.future : Future.value(open(namespace)),
        now: () => now,
      );
      await scope.select(guest);
      auth.change(identity(a));
      final opening = scope.select(a);
      final release = scope.state!.retainDraft();
      gate.complete(open(a));
      await expectLater(opening, throwsStateError);
      expect(scope.state!.repository!.store.namespace, guest);
      expect(identical(scope.state, old), isFalse);
      release();
    },
  );

  test(
    'account constructors cannot implicitly use fictional guest defaults',
    () {
      final store = open(a);
      final repository = BathroomRepository(store);
      expect(() => AppState(repository: repository), throwsArgumentError);
      expect(
        () => AppState(currentUserId: a.subject, repository: repository),
        throwsArgumentError,
      );
      expect(() => AppState.restore(store), throwsArgumentError);
      final state = AppState.restoreAccountForTesting(repository);
      expect(state.allBathrooms, isEmpty);
      state.dispose();
      store.close();
    },
  );

  test(
    'failed or mismatched opens preserve selected guest state and files',
    () async {
      scope.dispose();
      var fail = false;
      LocalStore? mismatched;
      scope = AccountStateScope.forTesting(
        auth: auth,
        now: () => now,
        openStore: (namespace) async {
          if (namespace == a) {
            if (fail) throw StateError('unavailable storage');
            return mismatched = open(b);
          }
          return open(namespace);
        },
      );
      await scope.select(guest);
      final original = scope.state!;
      auth.change(identity(a));
      await expectLater(scope.select(a), throwsStateError);
      expect(mismatched!.isClosed, isTrue);
      fail = true;
      await expectLater(scope.select(a), throwsStateError);
      expect(scope.state, same(original));
      expect(original.repository!.store.isClosed, isFalse);
      expect(original.allBathrooms, hasLength(6));
    },
  );

  test(
    'reselecting guest cancels an older pending account selection',
    () async {
      scope.dispose();
      final gate = Completer<LocalStore>();
      scope = AccountStateScope.forTesting(
        auth: auth,
        now: () => now,
        openStore: (namespace) =>
            namespace == a ? gate.future : Future.value(open(namespace)),
      );
      await scope.select(guest);
      final original = scope.state!;
      auth.change(identity(a));
      await expectLater(
        scope.select(
          guest,
          synchronizationForTesting: SyncWriteContext.forTesting(a),
        ),
        throwsArgumentError,
      );
      await expectLater(
        scope.select(
          a,
          synchronizationForTesting: SyncWriteContext.forTesting(b),
        ),
        throwsArgumentError,
      );
      final opening = scope.select(a);
      await scope.select(guest);
      final staleStore = open(a);
      gate.complete(staleStore);
      expect(await opening, isFalse);
      expect(staleStore.isClosed, isTrue);
      expect(scope.state, same(original));
    },
  );

  test('disposing during a store open closes the late connection', () async {
    scope.dispose();
    final gate = Completer<LocalStore>();
    final owner = AccountStateScope.forTesting(
      auth: auth,
      now: () => now,
      openStore: (_) => gate.future,
    );
    auth.change(identity(a));
    final opening = owner.select(a);
    owner.dispose();
    final lateStore = open(a);
    gate.complete(lateStore);
    expect(await opening, isFalse);
    expect(lateStore.isClosed, isTrue);
    scope = AccountStateScope.forTesting(
      auth: auth,
      now: () => now,
      openStore: (n) async => open(n),
    );
  });

  test('a disposed authentication adapter ignores a delayed renewal', () async {
    final adapter = FakeAuthSession(now: () => now)..change(identity(a));
    final gate = Completer<SessionIdentity>();
    final renewal = adapter.renew((_) => gate.future);
    adapter.dispose();
    gate.complete(identity(a));
    expect(await renewal, isFalse);
    expect(adapter.current, isNull);
  });

  test(
    'delayed pull after logout cannot write to a retired account store',
    () async {
      await select(a);
      final store = scope.state!.repository!.store;
      final gate = Completer<void>();
      final remote = FakeRemoteDataSource()..beforePull = () => gate.future;
      remote.pages['${a.key}:private'] = PullPage([
        RemoteChange('bathroom', 'remote-A', 1, payload: {'name': 'Privado A'}),
      ], 'checkpoint-A');
      final coordinator = SyncCoordinator(
        store: SyncStore(store),
        auth: auth,
        remote: remote,
        now: () => now,
      );
      final running = coordinator.synchronize();
      expect(remote.pullRequests, hasLength(1));
      auth.logout();
      await scope.select(guest);
      gate.complete();
      await running;
      final reopened = open(a);
      expect(reopened.database.select('SELECT * FROM remote_records'), isEmpty);
      expect(SyncStore(reopened).checkpoint('private'), isNull);
      reopened.close();
    },
  );

  for (final event in [
    'renewal',
    'expiry',
    'logout',
    'switch-back',
    'dispose',
  ]) {
    test('delayed synchronization response is invalidated by $event', () async {
      await select(a, queue: true);
      final state = scope.state!;
      state.createBathroom('Resposta atrasada');
      final store = state.repository!.store;
      final op = SyncStore(store).ready(now, 1).single;
      final gate = Completer<void>();
      final remote = FakeRemoteDataSource()..beforeSubmit = () => gate.future;
      final coordinator = SyncCoordinator(
        store: SyncStore(store),
        auth: auth,
        remote: remote,
        now: () => now,
      );
      final running = coordinator.synchronize();
      switch (event) {
        case 'renewal':
          await auth.renew((_) async => identity(a));
        case 'expiry':
          now += 60000;
          auth.checkExpiry();
        case 'logout':
          auth.logout();
          await scope.select(guest);
        case 'switch-back':
          await select(b);
          await select(a);
        case 'dispose':
          scope.dispose();
          scope = AccountStateScope.forTesting(
            auth: auth,
            openStore: (n) async => open(n),
            now: () => now,
          );
      }
      gate.complete();
      await running;
      expect(remote.pullRequests, isEmpty);
      if (store.isClosed) {
        final reopened = open(a);
        expect(SyncStore(reopened).ready(now, 1).single.id, op.id);
        reopened.close();
      } else {
        expect(SyncStore(store).ready(now, 1).single.id, op.id);
      }
    });
  }
}
