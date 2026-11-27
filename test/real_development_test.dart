import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/sync/account_projection.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/http_remote_data_source.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'production_auth_test.dart' show MemoryVault;
import '../tool/auth_device_preview.dart' show DevicePreviewTls;

void main() {
  final file = Platform.environment['BATH_DEVELOPMENT_CONFIG'];
  test(
    'all five isolated development accounts authenticate and restore only their own activity',
    () async {
      final config = jsonDecode(File(file!).readAsStringSync()) as Map;
      final configuration = AuthConfiguration.localDevelopment(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_PUBLISHABLE_KEY'] as String,
      );
      final old = HttpOverrides.current;
      HttpOverrides.global = DevicePreviewTls(
        config['BATH_DEVICE_CA_BASE64'] as String,
      );
      addTearDown(() => HttpOverrides.global = old);
      final accounts =
          (jsonDecode(
                    utf8.decode(
                      base64Decode(
                        config['BATH_LOCAL_TEST_ACCOUNTS'] as String,
                      ),
                    ),
                  )
                  as List)
              .cast<Map>();
      final cache = LocalStore(
        sqlite3.openInMemory(),
        namespace: DataNamespace.publicCatalogue(configuration.environment),
      );
      final publicRemote = HttpRemoteDataSource(
        endpoint: Uri.parse('${configuration.environment}/rest/v1/'),
        environment: configuration.environment,
        clientKey: configuration.clientKey,
        accessToken: (_) => null,
      );
      final catalogue = CommunityCatalogue(
        SyncCoordinator(
          store: SyncStore(cache),
          auth: FakeAuthSession(),
          remote: publicRemote,
          now: () => DateTime.now().millisecondsSinceEpoch,
          batchSize: 100,
        ),
        closeRemote: publicRemote.close,
      );
      addTearDown(catalogue.dispose);
      await catalogue.refresh();
      expect(catalogue.error, isNull);
      expect(catalogue.bathrooms.length, greaterThanOrEqualTo(12));
      expect(
        catalogue.bathrooms.where((b) => b.classification == 'official').length,
        greaterThanOrEqualTo(6),
      );
      expect(catalogue.reviews.length, greaterThanOrEqualTo(37));
      expect(catalogue.reviews.any((r) => r.tags.length >= 3), true);
      expect(catalogue.reviews.any((r) => r.tags.isEmpty), true);
      expect(catalogue.reviews.any((r) => r.rating == 0), true);
      expect(
        catalogue.reviews.any((r) => r.rating != r.rating.roundToDouble()),
        true,
      );
      expect(
        catalogue.bathrooms.any(
          (b) => !catalogue.reviews.any((r) => r.bathroomId == b.id),
        ),
        true,
      );
      final feedbackId = AppState.newEntityId();
      final feedback = {
        'report_id': feedbackId,
        'retry_key': AppState.newEntityId(),
        'category': 'other',
        'description':
            'Verificação automática A4 — exemplo fictício de feedback.',
        'app_version': '0.1.0-test-a4',
        'platform_version': 'Test',
        'screen_id': 'explore',
      };
      await publicRemote.submitFeedback(feedback);
      await publicRemote.submitFeedback(feedback); // lost acknowledgement retry
      for (var index = 0; index < accounts.length; index++) {
        final vault = MemoryVault();
        final auth = ProductionAuth(
          configuration,
          vault,
          restorationGuard: vault.guard,
        );
        await auth.login(
          accounts[index]['email'] as String,
          accounts[index]['password'] as String,
        );
        expect(auth.current, isNotNull);
        expect(auth.privateEmail, accounts[index]['email']);
        final local = LocalStore(
          sqlite3.openInMemory(),
          namespace: auth.current!.namespace,
        );
        final remote = HttpRemoteDataSource(
          endpoint: Uri.parse('${configuration.environment}/rest/v1/'),
          environment: configuration.environment,
          clientKey: configuration.clientKey,
          accessToken: (_) => auth.client.currentSession?.accessToken,
        );
        final state = AppState.restoreAccountForTesting(
          BathroomRepository(local),
        )..attachCommunity(catalogue);
        SyncStore(local).consent();
        final coordinator = SyncCoordinator(
          store: SyncStore(local),
          auth: auth,
          remote: remote,
          now: () => DateTime.now().millisecondsSinceEpoch,
          batchSize: 100,
        );
        await coordinator.synchronize();
        expect(coordinator.lastFailure, isNull);
        state.materializeCatalogue();
        AccountProjection(SyncStore(local)).apply();
        state.reloadAccountData();
        expect(
          state.visibleVisits.length,
          greaterThanOrEqualTo([9, 10, 18, 8, 0][index]),
        );
        expect(
          state.visibleReviews.length,
          greaterThanOrEqualTo([8, 8, 14, 7, 0][index]),
        );
        expect(
          state.visits.every((v) => v.userId == state.currentUserId),
          true,
        );
        expect(state.isModerator, index == 0);
        if (index == 0) {
          final reports = await remote.feedbackReports(auth.current!, 0);
          expect(reports.where((r) => r['id'] == feedbackId).length, 1);
          await remote.setFeedbackStatus(auth.current!, feedbackId, 'reviewed');
          await remote.setFeedbackStatus(auth.current!, feedbackId, 'resolved');
          expect(
            (await remote.feedbackReports(
              auth.current!,
              0,
            )).singleWhere((r) => r['id'] == feedbackId)['status'],
            'resolved',
          );
        } else {
          await expectLater(
            remote.feedbackReports(auth.current!, 0),
            throwsA(isA<RemoteFailure>()),
          );
        }
        expect(state.canCreateBathroom, index < 2);
        state.dispose();
        local.close();
        remote.close();
        await auth.logout();
        auth.dispose();
      }
    },
    skip: file == null,
  );
}
