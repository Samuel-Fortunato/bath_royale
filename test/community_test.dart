import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/private_sync_controller.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/account_projection.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/pages/bathroom_details.dart';

void main() {
  late LocalStore publicStore, local;
  late CommunityCatalogue catalogue;
  late AppState state;
  final namespace = DataNamespace.account('community-test', 'alice');
  setUp(() {
    publicStore = LocalStore(
      sqlite3.openInMemory(),
      namespace: DataNamespace.publicCatalogue(namespace.environment),
    );
    catalogue = CommunityCatalogue(
      SyncCoordinator(
        store: SyncStore(publicStore),
        auth: FakeAuthSession(),
        remote: FakeRemoteDataSource(),
        now: () => 1000,
      ),
    );
    local = LocalStore(sqlite3.openInMemory(), namespace: namespace);
    state = AppState.restoreAccountForTesting(
      BathroomRepository(
        local,
        syncContext: SyncWriteContext.account(namespace),
      ),
    )..attachCommunity(catalogue);
    SyncStore(publicStore).applyPull('catalogue', [
      RemoteChange(
        'bathroom',
        'shared',
        1,
        payload: {
          'id': 'shared',
          'name': 'Trono comum',
          'emoji': '👑',
          'accent': 2,
        },
      ),
      RemoteChange(
        'review',
        'public-review',
        1,
        payload: {
          'id': 'public-review',
          'bathroom_id': 'shared',
          'author_id': 'public-author',
          'username': 'explorador',
          'rating': 2.0,
          'paper': 1,
          'hygiene': 2,
          'comfort': 3,
          'aesthetics': 1,
          'tags': <Object>[],
          'comment': 'Comentário público',
        },
      ),
    ], 'initial');
  });
  tearDown(() {
    state.dispose();
    local.close();
    catalogue.dispose();
  });

  Review personal(String bathroom) {
    final visit = state.recordVisit(bathroom, visitedAt: DateTime.utc(2030));
    final review = Review(
      id: AppState.newEntityId(),
      visitId: visit.id,
      bathroomId: bathroom,
      authorId: namespace.subject,
      createdAt: visit.visitedAt,
      rating: 5,
      paperAvailability: 2,
      hygiene: 4,
      comfort: 4,
      aesthetics: 4,
      comment: 'Privado',
    );
    state.saveReview(review);
    return review;
  }

  test(
    'community aggregates exclude all unpublished personal reviews and private records',
    () {
      personal('shared');
      final entry = state.entries.single;
      expect(entry.communityRating, 2);
      expect(entry.reviewCount, 1);
      expect(entry.personalReview!.rating, 5);
      expect(state.communityReviewsFor('shared').single.username, 'explorador');
      expect(
        rankBathrooms(
          state.allBathrooms,
          catalogue.reviews,
          RankingMetric.overall,
        ).single.score,
        2,
      );
      expect(publicStore.database.select('SELECT * FROM visits'), isEmpty);
      expect(publicStore.database.select('SELECT * FROM outbox'), isEmpty);
      expect(
        jsonEncode(
          publicStore.database
              .select('SELECT payload FROM remote_records')
              .map((r) => Map.of(r))
              .toList(),
        ),
        isNot(contains('Privado')),
      );
    },
  );
  test(
    'acknowledged contribution refreshes the public cache without idle polling',
    () async {
      final publicRemote = catalogue.coordinator.remote as FakeRemoteDataSource;
      final privateRemote = FakeRemoteDataSource();
      final auth = FakeAuthSession()
        ..change(SessionIdentity(namespace, 100000));
      final controller = PrivateSyncController(
        state: state,
        coordinator: SyncCoordinator(
          store: SyncStore(local),
          auth: auth,
          remote: privateRemote,
          now: () => 1000,
          authorized: () => SyncStore(local).hasConsent,
        ),
        renew: () async {},
      );
      state.synchronization = controller;
      final b = state.createBathroom('Novo trono partilhado');
      expect(state.isAvailable(b.id), false);
      publicRemote.pages['${publicStore.namespace.key}:catalogue'] = PullPage([
        RemoteChange(
          'bathroom',
          b.id,
          2,
          payload: {
            'id': b.id,
            'name': b.name,
            'emoji': b.emoji,
            'accent': b.accent,
          },
        ),
      ], 'updated');
      await controller.enable();
      expect(state.isAvailable(b.id), true);
      expect(publicRemote.pullRequests.length, 1);
      final privatePulls = privateRemote.pullRequests.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(privateRemote.pullRequests.length, privatePulls);
      expect(publicRemote.pullRequests.length, 1);
      expect(
        state.entries.firstWhere((e) => e.bathroom.id == b.id).catalogueLabel,
        'Catálogo partilhado',
      );
    },
  );
  test(
    'explicit association composes visits and favourites without reparenting or publication',
    () {
      final private = Bathroom(
        id: 'private',
        name: 'Nome antigo',
        createdBy: namespace.subject,
      );
      state.repository!.createBathroom(private);
      state.reloadAccountData();
      final review = personal(private.id);
      state.toggleFavorite(private.id);
      state.materializeCatalogue();
      state.associateBathroom(private.id, 'shared');
      final entry = state.entries.single;
      expect(entry.bathroom.id, 'shared');
      expect(entry.activity.visitCount, 1);
      expect(entry.activity.isFavorite, true);
      expect(entry.personalReview!.id, review.id);
      expect(
        local.database.select('SELECT bathroom FROM visits').single['bathroom'],
        'private',
      );
      expect(
        local.database
            .select('SELECT bathroom FROM reviews')
            .single['bathroom'],
        'private',
      );
      expect(
        local.database.select(
          "SELECT * FROM outbox WHERE entity_type='publication'",
        ),
        isEmpty,
      );
      state.toggleFavorite('shared');
      expect(state.activityFor('shared').isFavorite, false);
      expect(local.database.select('SELECT * FROM favourites'), isEmpty);
      expect(
        () => state.associateBathroom(private.id, 'shared'),
        throwsStateError,
      );
    },
  );
  test(
    'public cache cannot overwrite an existing private row with a colliding ID',
    () {
      state.repository!.createBathroom(
        Bathroom(
          id: 'shared',
          name: 'Local preserved',
          createdBy: namespace.subject,
        ),
      );
      state.reloadAccountData();
      state.materializeCatalogue();
      expect(
        local.database.select('SELECT name FROM bathrooms').single['name'],
        'Local preserved',
      );
      expect(state.allBathrooms.single.name, 'Local preserved');
    },
  );
  test(
    'publication is explicit, durable, sequenced behind private review and username',
    () {
      final review = personal('shared');
      expect(
        () => state.publishReview(review, publish: true),
        throwsStateError,
      );
      state.setPublicUsername('alice_public');
      state.publishReview(review, publish: true);
      expect(state.isPublished(review.id), true);
      final row = local.database
          .select("SELECT * FROM outbox WHERE entity_type='publication'")
          .single;
      expect(jsonDecode(row['payload'] as String), {
        'review_id': review.id,
        'published': true,
      });
      expect(
        local.database.select(
          'SELECT * FROM outbox_dependencies WHERE operation_id=?',
          [row['operation_id']],
        ).length,
        2,
      );
      state.publishReview(review, publish: false);
      expect(state.isPublished(review.id), false);
      expect(state.visits.single.id, review.visitId);
      expect(state.reviews.single.id, review.id);
    },
  );
  test(
    'acknowledged username remains visible while bounded private feed catches up',
    () {
      state.setPublicUsername('alice_public');
      final sync = SyncStore(local);
      final op = sync.ready(1000, 1).single;
      sync.acknowledge(op, 10);
      sync.applyPull('private', [
        RemoteChange(
          'profile',
          namespace.subject,
          4,
          payload: {'username': 'old_name'},
        ),
      ], 'old');
      expect(state.publicUsername, 'alice_public');
      sync.applyPull('private', [
        RemoteChange(
          'profile',
          namespace.subject,
          11,
          payload: {'username': 'new_device'},
        ),
      ], 'new');
      expect(state.publicUsername, 'new_device');
    },
  );
  test(
    'anonymous cache browsing cannot queue any personal or community changes',
    () {
      final anonymous = AppState(
        currentUserId: 'public',
        bathrooms: [],
        reviews: [],
        visits: [],
        activities: [],
      )..attachCommunity(catalogue, anonymous: true);
      addTearDown(anonymous.dispose);
      expect(anonymous.entries.single.reviewCount, 1);
      expect(
        () => anonymous.recordVisit('shared', visitedAt: DateTime.now()),
        throwsStateError,
      );
      expect(() => anonymous.toggleFavorite('shared'), throwsStateError);
      expect(() => anonymous.createBathroom('Forbidden'), throwsStateError);
      expect(() => anonymous.setPublicUsername('forbidden'), throwsStateError);
      expect(publicStore.database.select('SELECT * FROM outbox'), isEmpty);
    },
  );
  test(
    'moderation removes community scores while retaining private visits and favourites',
    () {
      personal('shared');
      state.toggleFavorite('shared');
      SyncStore(publicStore).applyPull('catalogue', [
        RemoteChange(
          'review',
          'public-review',
          2,
          deleted: true,
          payload: {'_visibility': false},
        ),
        RemoteChange(
          'bathroom',
          'shared',
          2,
          deleted: true,
          payload: {'_visibility': false},
        ),
      ], 'hidden');
      expect(state.entries.single.reviewCount, 0);
      expect(state.visitsFor('shared').length, 1);
      expect(state.activityFor('shared').isFavorite, true);
      expect(state.isAvailable('shared'), false);
      expect(
        () => state.recordVisit('shared', visitedAt: DateTime.now()),
        throwsStateError,
      );
      SyncStore(publicStore).applyPull('catalogue', [
        RemoteChange(
          'bathroom',
          'shared',
          3,
          payload: {
            'id': 'shared',
            'name': 'Trono comum',
            'emoji': '👑',
            'accent': 2,
          },
        ),
      ], 'restored');
      expect(state.isAvailable('shared'), true);
    },
  );
  test(
    'failed duplicate contribution can be corrected or archived without releasing dependent writes',
    () {
      final b = state.createBathroom('Duplicado');
      expect(state.isAvailable(b.id), false);
      expect(
        () => state.recordVisit(b.id, visitedAt: DateTime.now()),
        throwsStateError,
      );
      final sync = SyncStore(local);
      final op = sync.ready(1000, 1).single;
      sync.reject(op, 'validation');
      sync.retryProblem(op.id, correctedText: 'Outro edifício piso 2');
      final corrected = sync.ready(1000, 1).single;
      expect(jsonDecode(corrected.payload), {
        'name': 'Outro edifício piso 2',
        'emoji': b.emoji,
        'accent': b.accent,
      });
      sync.reject(corrected, 'validation');
      sync.useAccountVersion(corrected.id);
      state.reloadAccountData();
      expect(state.allBathrooms.any((r) => r.id == b.id), false);
      expect(sync.archives.length, 2);
    },
  );
  test(
    'own shared-parent projection restores personal data even without a public cache',
    () {
      SyncStore(local).applyPull('private', [
        RemoteChange(
          'sharedBathroom',
          'hidden-parent',
          2,
          payload: {
            'id': 'hidden-parent',
            'name': 'Retido',
            'emoji': '🚽',
            'accent': 0,
          },
        ),
        RemoteChange(
          'visit',
          'own-visit',
          2,
          payload: {
            'id': 'own-visit',
            'owner_id': namespace.subject,
            'bathroom_id': 'hidden-parent',
            'visited_at': '2030-01-01T00:00:00Z',
          },
        ),
      ], 'private');
      AccountProjection(SyncStore(local)).apply();
      state.reloadAccountData();
      expect(state.visitsFor('hidden-parent').single.id, 'own-visit');
      expect(state.isAvailable('hidden-parent'), false);
    },
  );
  test(
    'v7 upgrade, offline cache and queued community actions survive restart unchanged',
    () async {
      final directory = Directory.systemTemp.createTempSync('a3-cache-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/account.sqlite';
      final publicPath = '${directory.path}/public.sqlite';
      var disk = LocalStore(sqlite3.open(path), namespace: namespace);
      final before = AppState.restoreAccountForTesting(
        BathroomRepository(
          disk,
          syncContext: SyncWriteContext.account(namespace),
        ),
      );
      final b = before.createBathroom('Preservado de A2');
      final v = before.recordVisit(b.id, visitedAt: DateTime.utc(2030));
      before.toggleFavorite(b.id);
      SyncStore(disk).consent();
      final original = disk.database
          .select('SELECT * FROM outbox')
          .map((r) => Map.of(r))
          .toList();
      before.dispose();
      disk.database.execute(
        'DROP TABLE bathroom_links; DROP TABLE catalogue_bathrooms',
      );
      disk.database.userVersion = 7;
      disk.close();
      disk = LocalStore(sqlite3.open(path), namespace: namespace);
      expect(disk.database.userVersion, 8);
      expect(disk.load()!.visits.single.id, v.id);
      expect(SyncStore(disk).hasConsent, true);
      expect(
        disk.database
            .select('SELECT * FROM outbox')
            .map((r) => Map.of(r))
            .toList(),
        original,
      );
      var cache = LocalStore(
        sqlite3.open(publicPath),
        namespace: publicStore.namespace,
      );
      SyncStore(cache).applyPull('catalogue', [
        RemoteChange(
          'bathroom',
          'offline',
          1,
          payload: {
            'id': 'offline',
            'name': 'Guardado offline',
            'emoji': '🚽',
            'accent': 0,
          },
        ),
      ], 'cached');
      cache.close();
      cache = LocalStore(
        sqlite3.open(publicPath),
        namespace: publicStore.namespace,
      );
      final remote = FakeRemoteDataSource()
        ..pullFailures.add(const RemoteFailure(RemoteFailureKind.transport));
      final offline = CommunityCatalogue(
        SyncCoordinator(
          store: SyncStore(cache),
          auth: FakeAuthSession(),
          remote: remote,
          now: () => 1000,
        ),
      );
      final restored = AppState.restoreAccountForTesting(
        BathroomRepository(
          disk,
          syncContext: SyncWriteContext.account(namespace),
        ),
      )..attachCommunity(offline);
      restored.setPublicUsername('offline_user');
      final operation = disk.database
          .select("SELECT * FROM outbox WHERE entity_type='profile'")
          .single;
      await offline.refresh();
      expect(offline.error, isNotNull);
      expect(restored.allBathrooms.any((b) => b.id == 'offline'), true);
      restored.dispose();
      disk.close();
      offline.dispose();
      disk = LocalStore(sqlite3.open(path), namespace: namespace);
      expect(
        disk.database
            .select("SELECT * FROM outbox WHERE entity_type='profile'")
            .single,
        operation,
      );
      expect(disk.load()!.visits.single.id, v.id);
      disk.close();
    },
  );
  testWidgets('community details remain usable at 320 px with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const BathroomDetailsPage(bathroomId: 'shared'),
        ),
      ),
    );
    await tester.tap(find.text('Avaliações'));
    await tester.pumpAndSettle();
    expect(find.text('@explorador'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'anonymous Explore, details and ranking show public content with no visit information',
    (tester) async {
      final anonymous = AppState(
        currentUserId: 'public',
        bathrooms: [],
        reviews: [],
        visits: [],
        activities: [],
      )..attachCommunity(catalogue, anonymous: true);
      addTearDown(anonymous.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: anonymous,
          child: const MaterialApp(home: HomePage()),
        ),
      );
      expect(find.text('Trono comum'), findsOneWidget);
      expect(find.text('Adicionar trono'), findsNothing);
      await tester.tap(find.text('Trono comum'));
      await tester.pumpAndSettle();
      expect(find.byType(BathroomDetailsPage), findsOneWidget);
      await tester.tap(find.text('Avaliações'));
      await tester.pumpAndSettle();
      expect(find.text('@explorador'), findsOneWidget);
      expect(find.text('Comentário público'), findsOneWidget);
      expect(find.textContaining('Criada:'), findsNothing);
      expect(find.textContaining('Ver experiência'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
