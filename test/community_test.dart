import 'dart:convert';
import 'package:bath_royale/models/bathroom_filters.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/private_sync_controller.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/pages/profile.dart';

void main() {
  final n = DataNamespace.account('a31-test', 'alice');
  late LocalStore local, public;
  late AppState state;
  late CommunityCatalogue catalogue;
  setUp(() {
    local = LocalStore(sqlite3.openInMemory(), namespace: n);
    public = LocalStore(
      sqlite3.openInMemory(),
      namespace: DataNamespace.publicCatalogue(n.environment),
    );
    SyncStore(public).applyPull('catalogue', [
      RemoteChange(
        'bathroom',
        'shared',
        1,
        payload: {
          'id': 'shared',
          'name': 'Trono comum',
          'emoji': '👑',
          'accent': 1,
          'classification': 'official',
        },
      ),
      RemoteChange(
        'review',
        'public-review',
        1,
        payload: {
          'id': 'public-review',
          'bathroom_id': 'shared',
          'rating': 2.0,
          'paper': 1,
          'hygiene': 2,
          'comfort': 3,
          'aesthetics': 1,
          'tags': <Object>[],
          'comment': 'Experiência anónima',
        },
      ),
    ], 'cached');
    catalogue = CommunityCatalogue(
      SyncCoordinator(
        store: SyncStore(public),
        auth: FakeAuthSession(),
        remote: FakeRemoteDataSource(),
        now: () => 1000,
      ),
    );
    state = AppState.restoreAccountForTesting(
      BathroomRepository(local, syncContext: SyncWriteContext.account(n)),
    )..attachCommunity(catalogue);
  });
  tearDown(() {
    state.dispose();
    local.close();
    catalogue.dispose();
  });
  Review review(String bathroom) {
    final v = state.recordVisit(bathroom, visitedAt: DateTime.utc(2030));
    final r = Review(
      id: AppState.newEntityId(),
      visitId: v.id,
      bathroomId: bathroom,
      authorId: n.subject,
      createdAt: v.visitedAt,
      rating: 5,
      paperAvailability: 2,
      hygiene: 4,
      comfort: 4,
      aesthetics: 4,
      comment: 'Nova avaliação',
    );
    state.saveReview(r);
    return r;
  }

  void permit() {
    SyncStore(local).applyPull('private', [
      RemoteChange(
        'capabilities',
        n.subject,
        1,
        payload: {'create_bathroom': true, 'moderator': false},
      ),
    ], 'cap');
  }

  test(
    'new shared reviews use anonymous submission commands; cache does not mix private scores',
    () {
      review('shared');
      final row = local.database
          .select("SELECT * FROM outbox WHERE entity_type='review'")
          .single;
      expect(row['operation_type'], 'createCommunityReview');
      expect(state.entries.single.communityRating, 2);
      expect(state.entries.single.personalReview!.rating, 5);
      expect(public.database.select('SELECT * FROM visits'), isEmpty);
      expect(catalogue.reviews.single.authorId, isEmpty);
      expect(state.entries.single.catalogueLabel, 'Oficial');
    },
  );
  test('creation entitlement defaults denied and revocation persists', () {
    expect(state.canCreateBathroom, false);
    expect(() => state.createBathroom('Sem poder'), throwsStateError);
    permit();
    final b = state.createBathroom('Com permissão');
    expect(state.isAvailable(b.id), false);
    expect(
      () => state.recordVisit(b.id, visitedAt: DateTime.now()),
      throwsStateError,
    );
    SyncStore(local).applyPull('private', [
      RemoteChange(
        'capabilities',
        n.subject,
        2,
        payload: {'create_bathroom': false, 'moderator': false},
      ),
    ], 'revoked');
    expect(state.canCreateBathroom, false);
  });
  test(
    'legacy private rows and references are preserved outside normal catalogue',
    () {
      final b = Bathroom(
        id: 'legacy',
        name: 'Privado anterior',
        createdBy: n.subject,
      );
      state.repository!.createBathroom(b);
      state.reloadAccountData();
      state.repository!.recordVisit(
        Visit(
          id: 'legacy-visit',
          bathroomId: 'legacy',
          userId: n.subject,
          visitedAt: DateTime.utc(2020),
        ),
      );
      state.reloadAccountData();
      expect(state.allBathrooms.any((r) => r.id == 'legacy'), true);
      expect(state.legacyBathrooms.single.id, 'legacy');
      expect(state.visibleBathrooms.map((b) => b.id), ['shared']);
      expect(state.visibleVisits, isEmpty);
      expect(
        local.database.select('SELECT bathroom FROM visits').single['bathroom'],
        'legacy',
      );
      expect(
        local.database
            .select(
              "SELECT * FROM outbox WHERE operation_type LIKE 'createCommunity%'",
            )
            .length,
        0,
      );
    },
  );
  test('post-sync refresh does not cause idle polling', () async {
    permit();
    final b = state.createBathroom('Novo');
    final auth = FakeAuthSession()..change(SessionIdentity(n, 100000));
    final remote = FakeRemoteDataSource();
    final controller = PrivateSyncController(
      state: state,
      coordinator: SyncCoordinator(
        store: SyncStore(local),
        auth: auth,
        remote: remote,
        now: () => 1000,
        authorized: () => SyncStore(local).hasConsent,
      ),
      renew: () async {},
    );
    state.synchronization = controller;
    final feed = catalogue.coordinator.remote as FakeRemoteDataSource;
    feed.pages['${public.namespace.key}:catalogue'] = PullPage([
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
    ], 'new');
    await controller.enable();
    expect(state.isAvailable(b.id), true);
    final count = remote.pullRequests.length;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(remote.pullRequests.length, count);
  });
  test(
    'v8 migration clears only obsolete public attribution, preserves private data and outbox',
    () {
      final dir = Directory.systemTemp.createTempSync('a31-migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/account.sqlite';
      var disk = LocalStore(sqlite3.open(path), namespace: n);
      final old = AppState.restoreAccountForTesting(
        BathroomRepository(disk, syncContext: SyncWriteContext.account(n)),
      );
      final b = old.createBathroom('Antigo');
      old.recordVisit(b.id, visitedAt: DateTime.utc(2020));
      SyncStore(disk).consent();
      final rows = jsonEncode(
        disk.database
            .select('SELECT * FROM outbox')
            .map((r) => Map.of(r))
            .toList(),
      );
      old.dispose();
      disk.database.execute('DROP TABLE catalogue_classifications');
      disk.database.execute('ALTER TABLE bathrooms DROP COLUMN accent_rgb');
      disk.database.userVersion = 8;
      disk.close();
      disk = LocalStore(sqlite3.open(path), namespace: n);
      expect(disk.database.userVersion, 10);
      expect(disk.load()!.visits.length, 1);
      expect(SyncStore(disk).hasConsent, true);
      expect(
        jsonEncode(
          disk.database
              .select('SELECT * FROM outbox')
              .map((r) => Map.of(r))
              .toList(),
        ),
        rows,
      );
      disk.close();
    },
  );
  test('offline anonymous reads cannot queue writes', () async {
    final anonymous = AppState(
      currentUserId: 'public',
      bathrooms: [],
      reviews: [],
      visits: [],
      activities: [],
    )..attachCommunity(catalogue, anonymous: true);
    addTearDown(anonymous.dispose);
    (catalogue.coordinator.remote as FakeRemoteDataSource).pullFailures.add(
      const RemoteFailure(RemoteFailureKind.transport),
    );
    await catalogue.refresh();
    expect(catalogue.error, isNotNull);
    expect(anonymous.entries.single.bathroom.name, 'Trono comum');
    expect(
      () => anonymous.recordVisit('shared', visitedAt: DateTime.now()),
      throwsStateError,
    );
    expect(() => anonymous.toggleFavorite('shared'), throwsStateError);
    expect(public.database.select('SELECT * FROM outbox'), isEmpty);
  });
  test(
    'community filters ignore personal scores and exclude unrated bathrooms',
    () {
      review(
        'shared',
      ); // Own private/local five stars must not replace the public two.
      final entry = state.entries.single;
      expect(entry.personalReview!.rating, 5);
      expect(entry.communityRating, 2);
      bool matches(BathroomFilterID id) =>
          bathroomFilters.singleWhere((f) => f.id == id).test(entry);
      expect(matches(BathroomFilterID.goodRating), false);
      expect(matches(BathroomFilterID.badRating), true);
      expect(matches(BathroomFilterID.clean), false);
      expect(matches(BathroomFilterID.confy), true);
      expect(matches(BathroomFilterID.paper), false);
      expect(matches(BathroomFilterID.official), true);
      SyncStore(public).applyPull('catalogue', [
        RemoteChange('review', 'public-review', 2, deleted: true),
      ], 'removed');
      final empty = state.entries.single;
      for (final f in bathroomFilters.where(
        (f) => [
          BathroomFilterID.goodRating,
          BathroomFilterID.badRating,
          BathroomFilterID.clean,
          BathroomFilterID.confy,
          BathroomFilterID.instagramable,
          BathroomFilterID.paper,
        ].contains(f.id),
      )) {
        expect(f.test(empty), false, reason: f.label);
      }
      expect(
        bathroomFilters
            .singleWhere((f) => f.id == BathroomFilterID.notReviewed)
            .test(empty),
        true,
      );
    },
  );
  testWidgets(
    'signed-out navigation contains only Explore, Rankings and account entry',
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
      expect(find.text('Coleção'), findsNothing);
      expect(find.text('Perfil'), findsNothing);
      expect(find.text('Conta'), findsOneWidget);
      expect(find.text('Por descobrir'), findsNothing);
      expect(find.byTooltip('Adicionar aos favoritos'), findsNothing);
      expect(find.byTooltip('Filtros'), findsOneWidget);
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      expect(find.text('★ 4 ou mais'), findsOneWidget);
      expect(find.text('Os meus tronos'), findsNothing);
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trono comum'));
      await tester.pumpAndSettle();
      expect(find.text('Visitas'), findsNothing);
      expect(find.text('A tua experiência'), findsNothing);
      await tester.tap(find.text('Avaliações'));
      await tester.pumpAndSettle();
      expect(find.text('Avaliação anónima'), findsNothing);
      expect(find.text('Experiência anónima'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'ordinary Settings hide administration and retain legacy recovery',
    (tester) async {
      state.repository!.createBathroom(
        const Bathroom(id: 'legacy', name: 'Antigo', createdBy: 'alice'),
      );
      state.reloadAccountData();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      expect(find.text('Moderação'), findsNothing);
      expect(find.text('Registos anteriores'), findsOneWidget);
      expect(find.textContaining('Nome público'), findsNothing);
      expect(find.textContaining('Associar'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
