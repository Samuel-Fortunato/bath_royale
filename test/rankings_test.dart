import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/pages/rankings.dart';
import 'package:bath_royale/theme/theme.dart';

void main() {
  test(
    'all ranking metrics exclude missing ratings, reverse deterministically and isolate users',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      for (final metric in RankingMetric.values) {
        final best = rankBathrooms(state.allBathrooms, state.reviews, metric);
        final worst = rankBathrooms(
          state.allBathrooms,
          state.reviews,
          metric,
          worst: true,
        );
        expect(best.length, 5);
        expect(best.first.score, greaterThanOrEqualTo(best.last.score));
        expect(worst.first.score, lessThanOrEqualTo(worst.last.score));
        expect(best.every((r) => r.count == 1), isTrue);
        expect(
          rankBathrooms(
            state.allBathrooms,
            state.reviews,
            metric,
            userId: 'stranger',
          ),
          isEmpty,
        );
        expect(
          rankBathrooms(
            state.allBathrooms.reversed,
            state.reviews.reversed,
            metric,
          ).map((r) => r.bathroom.id),
          best.map((r) => r.bathroom.id),
        );
      }
    },
  );
  test(
    'community counts repeat experiences while personal scope preserves zero',
    () {
      final state = AppState(currentUserId: 'visitor');
      addTearDown(state.dispose);
      final visit = state.recordVisit('0', visitedAt: DateTime.utc(2030));
      state.saveReview(
        Review(
          id: 'zero',
          visitId: visit.id,
          bathroomId: '0',
          authorId: 'visitor',
          createdAt: DateTime.utc(2030),
          rating: 0,
          paperAvailability: 0,
          hygiene: 0,
          comfort: 0,
          aesthetics: 0,
        ),
      );
      final community = rankBathrooms(
        state.allBathrooms,
        state.reviews,
        RankingMetric.overall,
      ).singleWhere((r) => r.bathroom.id == '0');
      expect(community.count, 2);
      expect(community.score, 2.35);
      final personal = rankBathrooms(
        state.allBathrooms,
        state.reviews,
        RankingMetric.overall,
        userId: 'visitor',
      );
      expect(personal.single.score, 0);
      expect(personal.single.count, 1);
    },
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets('ranking controls and detail navigation at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: RankingsPage()),
          ),
        ),
      );
      await tester.tap(find.text('Pessoal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Papel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Melhores primeiro'));
      await tester.pumpAndSettle();
      expect(find.text('Piores primeiro'), findsOneWidget);
      await tester.tap(find.text('CP - 2º Piso'));
      await tester.pumpAndSettle();
      expect(find.text('Comunidade'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
