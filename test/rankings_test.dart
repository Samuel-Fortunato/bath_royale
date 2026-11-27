import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/pages/rankings.dart';
import 'package:bath_royale/theme/theme.dart';

void main() {
  test('ranking resolves each eligible review once with linked identities', () {
    final state = AppState();
    addTearDown(state.dispose);
    var resolutions = 0;
    final rows = rankBathrooms(
      state.allBathrooms,
      state.reviews,
      RankingMetric.overall,
      bathroomIdentity: (id) {
        resolutions++;
        return id;
      },
    );
    expect(resolutions, state.reviews.length);
    expect(
      rows.map((r) => r.count).reduce((a, b) => a + b),
      state.reviews.length,
    );
  });
  testWidgets(
    'overall is default and category survives scope and mode switches',
    (tester) async {
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
      expect(find.byType(TabBar), findsNothing);
      await tester.tap(find.text('Por categoria'));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 4);
      await tester.tap(find.text('Estética'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Geral'));
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.textContaining(' / 5'), findsWidgets);
      await tester.tap(find.text('Pessoal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por categoria'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(TabBar));
      expect(DefaultTabController.of(context).index, 2);
      expect(find.textContaining(' / 4'), findsWidgets);
    },
  );

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
  testWidgets(
    'metric tabs preserve personal means, scales and repeated-review counts',
    (tester) async {
      final state = AppState(currentUserId: 'visitor');
      addTearDown(state.dispose);
      for (var i = 0; i < 2; i++) {
        final visit = state.recordVisit(
          '0',
          visitedAt: DateTime.utc(2030, 1, i + 1),
        );
        state.saveReview(
          Review(
            id: 'mean-$i',
            visitId: visit.id,
            bathroomId: '0',
            authorId: 'visitor',
            createdAt: visit.visitedAt,
            rating: i == 0 ? 4 : 0,
            hygiene: i == 0 ? 4 : 0,
            comfort: i == 0 ? 2 : 0,
            aesthetics: i == 0 ? 3 : 1,
            paperAvailability: i == 0 ? 2 : 0,
          ),
        );
      }
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
      final expected = ['2,0 / 5', '2,0 / 4', '1,0 / 4', '2,0 / 4', '1,0 / 2'];
      for (var i = 0; i < RankingMetric.values.length; i++) {
        if (i == 0) {
          expect(find.text(expected[i]), findsOneWidget);
          await tester.tap(find.text('Por categoria'));
          await tester.pumpAndSettle();
          continue;
        }
        await tester.ensureVisible(find.text(RankingMetric.values[i].label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(RankingMetric.values[i].label));
        await tester.pumpAndSettle();
        expect(find.text(expected[i]), findsOneWidget);
        expect(find.text('2 aval.'), findsOneWidget);
      }
      await tester.tap(find.text('Comunidade'));
      await tester.pumpAndSettle();
      expect(find.text('3 aval.'), findsOneWidget);
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
      await tester.tap(find.text('Por categoria'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Papel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Papel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Melhores'));
      await tester.pumpAndSettle();
      expect(find.text('Piores'), findsOneWidget);
      await tester.tap(find.text('CP - 2º Piso'));
      await tester.pumpAndSettle();
      expect(find.text('Comunidade'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
