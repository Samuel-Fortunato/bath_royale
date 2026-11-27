import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/account_projection.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/http_remote_data_source.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';

void main() {
  final path = Platform.environment['BATH_COMMUNITY_TEST_CONFIG'];
  if (path == null) {
    test(
      'real community suite requires the isolated community runner',
      () {},
      skip: true,
    );
    return;
  }
  final config =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  test(
    'real two-account contribution, private visits, public review, edit, withdrawal and offline cache',
    () async {
      final endpoint = Uri.parse(config['endpoint'] as String);
      const environment = 'isolated-community-test';
      final sessions = [
        config['a'] as Map<String, dynamic>,
        config['b'] as Map<String, dynamic>,
      ];
      final publicLocal = LocalStore(
        sqlite3.openInMemory(),
        namespace: DataNamespace.publicCatalogue(environment),
      );
      final remote = HttpRemoteDataSource.forTesting(
        endpoint: endpoint,
        environment: environment,
        accessToken: (session) =>
            sessions.firstWhere(
                  (s) => (s['user'] as Map)['id'] == session.namespace.subject,
                )['access_token']
                as String,
      );
      final catalogue = CommunityCatalogue(
        SyncCoordinator(
          store: SyncStore(publicLocal),
          auth: FakeAuthSession(),
          remote: remote,
          now: () => DateTime.now().millisecondsSinceEpoch,
          batchSize: 100,
        ),
      );
      addTearDown(catalogue.dispose);
      addTearDown(remote.close);
      await catalogue.refresh();
      final stores = <LocalStore>[],
          states = <AppState>[],
          syncs = <SyncCoordinator>[];
      for (final session in sessions) {
        final n = DataNamespace.account(
          environment,
          (session['user'] as Map)['id'] as String,
        );
        final local = LocalStore(sqlite3.openInMemory(), namespace: n);
        final state = AppState.restoreAccountForTesting(
          BathroomRepository(local, syncContext: SyncWriteContext.account(n)),
        )..attachCommunity(catalogue);
        final auth = FakeAuthSession()
          ..change(
            SessionIdentity(n, DateTime.now().millisecondsSinceEpoch + 3600000),
          );
        stores.add(local);
        states.add(state);
        syncs.add(
          SyncCoordinator(
            store: SyncStore(local),
            auth: auth,
            remote: remote,
            now: () => DateTime.now().millisecondsSinceEpoch,
            batchSize: 100,
            authorized: () => SyncStore(local).hasConsent,
          ),
        );
        addTearDown(() {
          state.dispose();
          local.close();
          auth.dispose();
        });
      }
      Future<void> sync(int index) async {
        final coordinator = syncs[index];
        for (var page = 0; page < 30; page++) {
          await coordinator.synchronize();
          expect(coordinator.lastFailure, isNull);
          states[index].materializeCatalogue();
          AccountProjection(coordinator.store).apply();
          states[index].reloadAccountData();
          if (!coordinator.moreWork) break;
        }
        expect(coordinator.store.problems, isEmpty);
        expect(coordinator.store.pendingCount, 0);
      }

      final a = states[0], b = states[1];
      final shared = a.createBathroom(
        'Flutter community ${AppState.newEntityId()}',
      );
      // Nothing transfers before acceptance, including contributions.
      await syncs[0].synchronize();
      expect(syncs[0].store.pendingCount, 1);
      SyncStore(stores[0]).consent();
      SyncStore(stores[1]).consent();
      await sync(0);
      await catalogue.refresh();
      expect(b.allBathrooms.any((r) => r.id == shared.id), true);
      final visit = a.recordVisit(
        shared.id,
        visitedAt: DateTime.utc(2031, 2, 3, 4, 5, 6),
      );
      final review = Review(
        id: AppState.newEntityId(),
        visitId: visit.id,
        bathroomId: shared.id,
        authorId: a.currentUserId,
        createdAt: visit.visitedAt,
        rating: 5,
        paperAvailability: 2,
        hygiene: 4,
        comfort: 4,
        aesthetics: 4,
        comment: 'Só fica público após publicar',
      );
      a.saveReview(review);
      a.toggleFavorite(shared.id);
      a.setPublicUsername(
        'flutter_${AppState.newEntityId().replaceAll('-', '').substring(0, 12)}',
      );
      await sync(0);
      await sync(1);
      await catalogue.refresh();
      expect(b.visits, isEmpty);
      expect(b.reviews, isEmpty);
      expect(b.activityFor(shared.id).isFavorite, false);
      expect(b.communityReviewsFor(shared.id), isEmpty);
      a.publishReview(review, publish: true);
      await sync(0);
      await catalogue.refresh();
      expect(b.communityReviewsFor(shared.id).single.rating, 5);
      expect(
        b.entries.firstWhere((e) => e.bathroom.id == shared.id).reviewCount,
        1,
      );
      expect(
        rankBathrooms(
          b.allBathrooms,
          catalogue.reviews,
          RankingMetric.overall,
        ).firstWhere((r) => r.bathroom.id == shared.id).score,
        5,
      );
      // Independent account cannot receive the visit, exact chronology, favourites or email.
      expect(
        jsonEncode(
          publicLocal.database
              .select(
                "SELECT payload FROM remote_records WHERE entity_type='review'",
              )
              .map((r) => Map.of(r))
              .toList(),
        ),
        isNot(contains(visit.id)),
      );
      expect(
        jsonEncode(
          publicLocal.database
              .select(
                "SELECT payload FROM remote_records WHERE entity_type='review'",
              )
              .map((r) => Map.of(r))
              .toList(),
        ),
        isNot(contains((sessions[0]['user'] as Map)['email'])),
      );
      a.publishReview(review, publish: false);
      await sync(0);
      await catalogue.refresh();
      expect(b.communityReviewsFor(shared.id), isEmpty);
      expect(a.visitsFor(shared.id).single.id, visit.id);
      expect(a.activityFor(shared.id).isFavorite, true);
      // A second device restores the same account's shared-parent references and history.
      final another = LocalStore(
        sqlite3.openInMemory(),
        namespace: stores[0].namespace,
      );
      addTearDown(another.close);
      final otherState = AppState.restoreAccountForTesting(
        BathroomRepository(another),
      )..attachCommunity(catalogue);
      addTearDown(otherState.dispose);
      SyncStore(another).consent();
      final otherSync = SyncCoordinator(
        store: SyncStore(another),
        auth: syncs[0].auth,
        remote: remote,
        now: () => DateTime.now().millisecondsSinceEpoch,
        batchSize: 100,
      );
      await otherSync.synchronize();
      otherState.materializeCatalogue();
      AccountProjection(SyncStore(another)).apply();
      otherState.reloadAccountData();
      expect(otherState.visitsFor(shared.id).single.id, visit.id);
      expect(otherState.activityFor(shared.id).isFavorite, true);
      // Cache reads do not require a network request.
      expect(catalogue.bathrooms.any((r) => r.id == shared.id), true);
    },
  );
}
