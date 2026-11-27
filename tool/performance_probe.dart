/// Android release/profile-only probe. No device files, accounts or network.
/// Build with BATH_PERFORMANCE_PROBE=true and the isolated application ID.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/app.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/community_review.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';

class CountingCatalogue extends CommunityCatalogue {
  int bathroomReads = 0, reviewReads = 0;
  CountingCatalogue(super.coordinator);
  @override
  List<Bathroom> get bathrooms {
    bathroomReads++;
    return super.bathrooms;
  }

  @override
  List<CommunityReview> get reviews {
    reviewReads++;
    return super.reviews;
  }
}

void report(String name, Map<String, Object?> values) =>
    debugPrintSynchronously('A61 ${jsonEncode({'name': name, ...values})}');

T measure<T>(String name, T Function() action) {
  final watch = Stopwatch()..start();
  final result = action();
  report(name, {'us': watch.elapsedMicroseconds});
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) throw StateError('Use release or profile mode');
  report('mode', {'release': kReleaseMode});
  AppState? display;
  for (final size in [34, 100]) {
    final ns = DataNamespace.account('fictional-performance', 'probe');
    final public = LocalStore(
      sqlite3.openInMemory(),
      namespace: DataNamespace.publicCatalogue(ns.environment),
    );
    final changes = <RemoteChange>[
      for (var i = 0; i < size; i++)
        RemoteChange(
          'bathroom',
          'b$i',
          1,
          payload: {
            'id': 'b$i',
            'name': 'Trono fictício $i',
            'emoji': '🚽',
            'accent': i % 6,
            'classification': 'official',
          },
        ),
      for (var i = 0; i < size * 10; i++)
        RemoteChange(
          'review',
          'r$i',
          1,
          payload: {
            'id': 'r$i',
            'bathroom_id': 'b${i % size}',
            'rating': i % 6,
            'paper': i % 3,
            'hygiene': i % 5,
            'comfort': i % 5,
            'aesthetics': i % 5,
            'tags': <Object?>[],
            'comment': 'Dados fictícios de medição',
          },
        ),
    ];
    SyncStore(public).applyPull('catalogue', changes, 'fixture');
    final catalogue = CountingCatalogue(
      SyncCoordinator(
        store: SyncStore(public),
        auth: FakeAuthSession(),
        remote: FakeRemoteDataSource(),
        now: () => 1000,
      ),
    );
    final local = LocalStore(sqlite3.openInMemory(), namespace: ns);
    final state = AppState.restoreAccountForTesting(BathroomRepository(local))
      ..attachCommunity(catalogue);
    measure('$size/materialize', state.materializeCatalogue);
    local.transaction(() {
      for (var i = 0; i < size * 10; i++) {
        final date = DateTime.utc(2026).add(Duration(minutes: i));
        final visit = Visit(
          id: 'v$i',
          bathroomId: 'b${i % size}',
          userId: ns.subject,
          visitedAt: date,
        );
        local.insertVisit(visit);
        if (i.isEven) {
          local.writeReview(
            Review(
              id: 'own$i',
              visitId: visit.id,
              bathroomId: visit.bathroomId,
              authorId: ns.subject,
              createdAt: date,
              rating: i % 6,
              paperAvailability: i % 3,
              hygiene: i % 5,
              comfort: i % 5,
              aesthetics: i % 5,
            ),
            isNew: true,
          );
        }
      }
    });
    state.reloadAccountData();
    catalogue.bathroomReads = catalogue.reviewReads = 0;
    for (var run = 0; run < 3; run++) {
      final entries = measure('$size/entries/$run', () => state.entries);
      if (entries.length != size) throw StateError('Wrong entry count');
      final ranked = measure(
        '$size/rankings/$run',
        () => rankBathrooms(
          state.visibleBathrooms,
          catalogue.reviews,
          RankingMetric.overall,
          bathroomIdentity: state.sharedIdentity,
        ),
      );
      if (ranked.length != size) throw StateError('Wrong ranking count');
    }
    report('$size/reads', {
      'bathrooms': catalogue.bathroomReads,
      'reviews': catalogue.reviewReads,
      'visits': state.visits.length,
    });
    measure('$size/materialize-again', state.materializeCatalogue);
    if (display == null) {
      display = state;
    } else {
      state.dispose();
      local.close();
      catalogue.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final frames = <FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback(frames.addAll);
  runApp(ChangeNotifierProvider.value(value: display!, child: const MainApp()));
  await Future<void>.delayed(const Duration(seconds: 3));
  // Same four destinations and refresh as the app. Coordinates use view size.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  for (var round = 0; round < 3; round++) {
    for (final fraction in [.375, .625, .875, .125]) {
      final point = Offset(size.width * fraction, size.height - 55);
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(position: point),
      );
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(position: point),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await display.community!.refresh();
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  report('frames', {
    'count': frames.length,
    'build_over_16ms': frames
        .where((f) => f.buildDuration.inMicroseconds > 16667)
        .length,
    'raster_over_16ms': frames
        .where((f) => f.rasterDuration.inMicroseconds > 16667)
        .length,
    'max_build_us': frames
        .map((f) => f.buildDuration.inMicroseconds)
        .fold<int>(0, (a, b) => a > b ? a : b),
    'max_raster_us': frames
        .map((f) => f.rasterDuration.inMicroseconds)
        .fold<int>(0, (a, b) => a > b ? a : b),
  });
  report('done', {});
  WidgetsBinding.instance.removeTimingsCallback(frames.addAll);
}
