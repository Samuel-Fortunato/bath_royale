// Disposable integration fixture. No application bootstrap or credential storage.
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/http_remote_data_source.dart';

Future<void> main(List<String> args) async {
  final config =
      jsonDecode(
            File(
              Platform.environment['BATH_SYNC_TEST_CONFIG']!,
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final scope = DataNamespace.account(
    config['environment'] as String,
    config['a']['user']['id'] as String,
  );
  final store = LocalStore(sqlite3.open(args[1]), namespace: scope);
  try {
    if (args[0] == 'create') {
      BathroomRepository(
        store,
        syncContext: SyncWriteContext.forTesting(scope),
      ).createBathroom(
        Bathroom(
          id: const Uuid().v4(),
          name: 'Reinício fictício',
          createdBy: scope.subject,
        ),
      );
    } else if (args[0] == 'commitWithoutAck') {
      final remote = HttpRemoteDataSource.forTesting(
        endpoint: Uri.parse(config['endpoint'] as String),
        environment: scope.environment,
        accessToken: (_) => config['a']['access_token'] as String,
      );
      try {
        await remote.submit(
          SessionIdentity(scope, DateTime.now().millisecondsSinceEpoch + 60000),
          SyncStore(store).ready(0, 1).single,
        );
        // Process exits after a real server commit, without local acknowledgment.
      } finally {
        remote.close();
      }
    } else {
      throw ArgumentError('Unknown fixture step');
    }
  } finally {
    store.close();
  }
}
