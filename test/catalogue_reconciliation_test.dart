import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'redesign_test.dart' show mount;
import 'package:bath_royale/app.dart';
import 'package:bath_royale/pages/experience_details.dart';
import 'package:bath_royale/pages/bathroom_details.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/account_projection.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';

void main() {
  final namespace = DataNamespace.account('reconciliation', 'owner');
  late Directory directory;
  late LocalStore account, public;
  late AppState state;
  late CommunityCatalogue catalogue;
  late FakeRemoteDataSource remote;

  RemoteChange bathroom(
    String id,
    int revision, {
    String name = 'Trono antigo',
    String emoji = '🚽',
    int accent = 1,
    int? rgb,
    String classification = 'official',
  }) => RemoteChange(
    'bathroom',
    id,
    revision,
    payload: {
      'id': id,
      'name': name,
      'emoji': emoji,
      'accent': accent,
      'accent_rgb': rgb,
      'classification': classification,
    },
  );

  void open() {
    account = LocalStore(
      sqlite3.open('${directory.path}/account.sqlite'),
      namespace: namespace,
    );
    public = LocalStore(
      sqlite3.open('${directory.path}/public.sqlite'),
      namespace: DataNamespace.publicCatalogue(namespace.environment),
    );
    remote = FakeRemoteDataSource();
    catalogue = CommunityCatalogue(
      SyncCoordinator(
        store: SyncStore(public),
        auth: FakeAuthSession(),
        remote: remote,
        now: () => 1000,
      ),
    );
    state = AppState.restoreAccountForTesting(
      BathroomRepository(
        account,
        syncContext: SyncWriteContext.account(namespace),
      ),
    )..attachCommunity(catalogue);
  }

  void close() {
    state.dispose();
    account.close();
    catalogue.dispose();
  }

  void apply(List<RemoteChange> changes, [String checkpoint = 'next']) {
    SyncStore(public).applyPull('catalogue', changes, checkpoint);
    catalogue.notifyListeners();
  }

  String rows(String table) => jsonEncode(
    account.database
        .select('SELECT * FROM $table')
        .map((r) => Map.of(r))
        .toList(),
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'catalogue-reconciliation-',
    );
    open();
    apply([bathroom('shared', 1)]);
  });
  tearDown(() {
    close();
    directory.deleteSync(recursive: true);
  });

  test(
    'existing installation reconciles 36 cached parents to 30 without losing personal data or pending operations',
    () {
      apply([for (var i = 1; i < 36; i++) bathroom('bathroom-$i', 1)]);
      final visit = state.recordVisit(
        'bathroom-1',
        visitedAt: DateTime.utc(2026),
      );
      state.saveReview(
        Review(
          id: 'review',
          visitId: visit.id,
          bathroomId: visit.bathroomId,
          authorId: namespace.subject,
          createdAt: visit.visitedAt,
          rating: 4,
          paperAvailability: 2,
          hygiene: 3,
          comfort: 3,
          aesthetics: 3,
        ),
      );
      state.toggleFavorite(visit.bathroomId);
      final before = {
        for (final table in [
          'visits',
          'reviews',
          'favourites',
          'outbox',
          'outbox_dependencies',
        ])
          table: rows(table),
      };
      expect(state.visibleBathrooms, hasLength(36));
      // Reopen the same files, as an in-place application update would.
      close();
      open();
      apply([
        for (var i = 1; i <= 6; i++)
          RemoteChange('bathroom', 'bathroom-$i', 2, deleted: true),
      ]);
      expect(state.visibleBathrooms, hasLength(30));
      expect(state.allBathrooms, hasLength(36));
      expect(state.visibleVisits.single.id, visit.id);
      expect(state.visibleReviews.single.id, 'review');
      expect(state.activityFor(visit.bathroomId).isFavorite, true);
      expect(state.isShared(visit.bathroomId), true);
      expect(state.isAvailable(visit.bathroomId), false);
      expect(
        () =>
            state.recordVisit(visit.bathroomId, visitedAt: DateTime.utc(2027)),
        throwsStateError,
      );
      for (final table in before.keys) {
        expect(rows(table), before[table], reason: table);
      }
      close();
      open();
      expect(state.visibleBathrooms, hasLength(30));
      expect(state.visits.single.id, visit.id);
      expect(state.activityFor(visit.bathroomId).isFavorite, true);
    },
  );

  test(
    'hidden entries disappear and restore with changed names, emoji, RGB and classification',
    () {
      apply([
        RemoteChange(
          'bathroom',
          'shared',
          2,
          deleted: true,
          payload: {'_visibility': false},
        ),
      ]);
      expect(state.visibleBathrooms, isEmpty);
      expect(state.allBathrooms.single.name, 'Trono antigo');
      apply([
        bathroom(
          'shared',
          3,
          name: 'Trono restaurado',
          emoji: '👑',
          accent: 4,
          rgb: 0x123456,
          classification: 'community',
        ),
      ]);
      final restored = state.visibleBathrooms.single;
      expect(restored.name, 'Trono restaurado');
      expect(restored.emoji, '👑');
      expect(restored.accent, 4);
      expect(restored.accentRgb, 0x123456);
      expect(restored.classification, 'community');
      // Hide again: historical/offline metadata must retain the last known values.
      apply([
        RemoteChange(
          'bathroom',
          'shared',
          4,
          deleted: true,
          payload: {'_visibility': false},
        ),
      ]);
      close();
      open();
      expect(state.visibleBathrooms, isEmpty);
      expect(state.allBathrooms.single.name, restored.name);
      expect(state.allBathrooms.single.emoji, restored.emoji);
      expect(state.allBathrooms.single.accentRgb, restored.accentRgb);
      expect(state.allBathrooms.single.classification, 'community');
    },
  );

  test('terminal tombstones reject stale and newer resurrection', () {
    apply([RemoteChange('bathroom', 'shared', 4, deleted: true)]);
    apply([bathroom('shared', 2), bathroom('shared', 5)]);
    expect(state.visibleBathrooms, isEmpty);
    expect(state.allBathrooms.single.id, 'shared');
    expect(
      public.database
          .select("SELECT deleted FROM remote_records WHERE entity_id='shared'")
          .single['deleted'],
      1,
    );
  });

  test(
    'bounded pages and failed/offline refresh retain unseen entries and checkpoint across restart',
    () async {
      apply([bathroom('unseen', 1)]);
      remote.pages['${public.namespace.key}:catalogue'] = PullPage([
        bathroom('shared', 2, name: 'Novo nome'),
      ], 'partial');
      await catalogue.refresh();
      expect(state.visibleBathrooms, hasLength(2));
      expect(account.load()!.bathrooms.first.name, 'Novo nome');
      remote.pullFailures.add(const RemoteFailure(RemoteFailureKind.transport));
      await catalogue.refresh();
      expect(catalogue.error, isNotNull);
      expect(SyncStore(public).checkpoint('catalogue'), 'partial');
      close();
      open();
      expect(state.visibleBathrooms, hasLength(2));
      expect(state.visibleBathrooms.first.name, 'Novo nome');
      expect(state.visibleBathrooms.last.id, 'unseen');
    },
  );

  test(
    'account projection updates shared metadata and cannot make public withdrawals visible',
    () {
      void project(
        int revision, {
        bool deleted = false,
        String name = 'Conta atualizada',
      }) {
        SyncStore(account).applyPull('private', [
          RemoteChange(
            'sharedBathroom',
            'shared',
            revision,
            deleted: deleted,
            payload: deleted
                ? {}
                : {
                    'name': name,
                    'emoji': '✨',
                    'accent': 3,
                    'accent_rgb': 0xabcdef,
                  },
          ),
        ], 'private-$revision');
        AccountProjection(SyncStore(account)).apply();
      }

      project(1);
      expect(account.load()!.bathrooms.single.name, 'Conta atualizada');
      state.reloadAccountData();
      expect(
        account.load()!.bathrooms.single.name,
        'Trono antigo',
      ); // Current public metadata wins.
      state.toggleFavorite('shared');
      final favourite = rows('favourites'), pending = rows('outbox');
      apply([
        RemoteChange(
          'bathroom',
          'shared',
          2,
          deleted: true,
          payload: {'_visibility': false},
        ),
      ]);
      project(2);
      state.reloadAccountData();
      expect(state.visibleBathrooms, isEmpty);
      project(3, deleted: true);
      expect(rows('favourites'), favourite);
      expect(rows('outbox'), pending);
      expect(account.load()!.bathrooms.single.name, 'Conta atualizada');
    },
  );

  test(
    'pending contributions stay visible until explicit public withdrawal',
    () {
      SyncStore(account).applyPull('private', [
        RemoteChange(
          'capabilities',
          namespace.subject,
          1,
          payload: {'create_bathroom': true},
        ),
      ], 'capabilities');
      final created = state.createBathroom('Contribuição pendente');
      final pending = rows('outbox');
      expect(state.visibleBathrooms.any((b) => b.id == created.id), true);
      expect(state.isAvailable(created.id), false);
      apply([
        RemoteChange(
          'bathroom',
          created.id,
          2,
          deleted: true,
          payload: {'_visibility': false},
        ),
      ]);
      expect(state.visibleBathrooms.any((b) => b.id == created.id), false);
      expect(rows('outbox'), pending);
    },
  );

  test('account bathroom tombstones retain shared favourites and parents', () {
    state.toggleFavorite('shared');
    account.database.execute("UPDATE outbox SET state='acknowledged'");
    final favourites = rows('favourites'), operations = rows('outbox');
    SyncStore(account).applyPull('private', [
      RemoteChange('bathroom', 'shared', 2, deleted: true),
    ], 'removed');
    AccountProjection(SyncStore(account)).apply();
    expect(account.load()!.bathrooms.single.id, 'shared');
    expect(rows('favourites'), favourites);
    expect(rows('outbox'), operations);
  });

  testWidgets('diary opens historical experiences after catalogue deletion', (
    tester,
  ) async {
    final visit = state.recordVisit('shared', visitedAt: DateTime.utc(2026));
    apply([RemoteChange('bathroom', 'shared', 2, deleted: true)]);
    await mount(tester, state, const MainApp());
    await tester.tap(find.text('Coleção').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diário'));
    await tester.pumpAndSettle();
    expect(find.text('Trono antigo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Trono antigo'));
    await tester.pumpAndSettle();
    expect(find.byType(ExperienceDetailsPage), findsOneWidget);
    expect(state.visits.single.id, visit.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'open bathroom details handle a catalogue withdrawal without crashing',
    (tester) async {
      await mount(
        tester,
        state,
        const BathroomDetailsPage(bathroomId: 'shared'),
      );
      apply([RemoteChange('bathroom', 'shared', 2, deleted: true)]);
      await tester.pumpAndSettle();
      expect(
        find.text('Esta casa de banho já não está disponível no catálogo.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'failed catalogue page rolls back removals, metadata and checkpoint atomically',
    () {
      expect(
        () => SyncStore(public).applyPull('catalogue', [
          RemoteChange('bathroom', 'shared', 2, deleted: true),
          RemoteChange(
            'bathroom',
            'invalid',
            3,
            payload: {'invalid': Object()},
          ),
        ], 'broken'),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(SyncStore(public).checkpoint('catalogue'), 'next');
      expect(state.visibleBathrooms.single.id, 'shared');
    },
  );
}
