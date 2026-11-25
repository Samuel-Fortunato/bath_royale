import 'dart:io';
import 'package:bath_royale/pages/experience_details.dart';
import 'dart:ui' as ui;
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/ranking.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/pages/collection.dart';
import 'package:bath_royale/pages/profile.dart';
import 'package:bath_royale/pages/rankings.dart';
import 'package:bath_royale/pages/bathroom_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'redesign_test.dart' show mount, tap;
import 'package:bath_royale/state/app_state.dart';

AppState catalogue({int count = 100}) => AppState(
  bathrooms: [
    for (var i = 0; i < count; i++)
      Bathroom(
        id: '$i',
        name: 'Trono $i — nome completo da casa de banho',
        createdBy: 'local',
      ),
  ],
  visits: [
    for (var i = 0; i < 100 && count > 0; i++)
      Visit(
        id: 'visit-$i',
        bathroomId: '0',
        userId: 'local-user',
        visitedAt: DateTime(2026, 7, 2, 0, i),
      ),
    if (count > 0)
      Visit(
        id: 'previous',
        bathroomId: '0',
        userId: 'local-user',
        visitedAt: DateTime(2026, 7, 1, 23, 59),
      ),
  ],
  reviews: count == 0
      ? []
      : [
          Review(
            id: 'zero',
            visitId: 'visit-99',
            bathroomId: '0',
            authorId: 'local-user',
            createdAt: DateTime(2026, 7, 3),
            rating: 0,
            hygiene: 0,
            comfort: 0,
            aesthetics: 0,
            paperAvailability: 0,
          ),
        ],
  currentUserId: 'local-user',
);

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_SESSION3')) return;
  await tester.runAsync(() async {
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/session3-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    const fontPath = String.fromEnvironment('SESSION3_FONT');
    if (fontPath.isNotEmpty) {
      final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
      const emojiPath = String.fromEnvironment('SESSION3_EMOJI');
      if (emojiPath.isNotEmpty) {
        final emoji = await File(emojiPath).readAsBytes();
        await (FontLoader(
          'Noto Color Emoji',
        )..addFont(Future.value(emoji.buffer.asByteData()))).load();
      }
      final bytes = await File(fontPath).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
  });
  testWidgets(
    'collection counts unique discoveries, keeps tabs independent and diary optional',
    (tester) async {
      final state = catalogue();
      addTearDown(state.dispose);
      state.toggleFavorite('1');
      await mount(tester, state, const Scaffold(body: CollectionPage()));
      expect(find.text('1 / 100'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.text('✓ Descoberta'), findsOneWidget);
      expect(find.text('○ Por descobrir'), findsWidgets);
      expect(find.textContaining('Trono 99'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      expect(position, greaterThan(0));
      await tap(tester, find.text('Diário'));
      expect(find.text('02/07/2026'), findsOneWidget);
      expect(find.text('01:39 · 0,0 / 5 ★'), findsOneWidget);
      expect(find.text('01:38'), findsOneWidget);
      expect(find.textContaining('pendente'), findsNothing);
      expect(find.byType(ListTile).evaluate().length, lessThan(20));
      await tester.scrollUntilVisible(
        find.text('01/07/2026'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('01/07/2026'), findsOneWidget);
      await tap(tester, find.text('Tronos'));
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        position,
      );
    },
  );

  testWidgets('empty catalogue has zero progress and empty diary/favourites', (
    tester,
  ) async {
    final state = catalogue(count: 0);
    addTearDown(state.dispose);
    await mount(tester, state, const Scaffold(body: CollectionPage()));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0,
    );
    expect(find.text('0 / 0'), findsOneWidget);
    await tap(tester, find.text('Diário'));
    expect(find.text('O teu diário começa na próxima visita.'), findsOneWidget);
    await mount(tester, state, const Scaffold(body: FavouritesList()));
    expect(find.textContaining('Guarda os teus tronos'), findsOneWidget);
  });

  testWidgets(
    'profile routes reuse favourites and complete diary with detail navigation',
    (tester) async {
      final state = catalogue(count: 2);
      addTearDown(state.dispose);
      state.toggleFavorite('1');
      await mount(tester, state, const Scaffold(body: ProfilePage()));
      expect(find.text('101'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.textContaining('Trono 0'), findsNWidgets(2));
      expect(find.text('Histórico de atividade'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Os meus favoritos'));
      expect(find.byType(FavouritesList), findsOneWidget);
      await tap(tester, find.textContaining('Trono 1'));
      expect(find.byType(BathroomDetailsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await mount(
        tester,
        state,
        const Scaffold(body: CollectionPage(initialTab: 1)),
      );
      expect(find.byType(VisitDiary), findsOneWidget);
      await tap(tester, find.textContaining('Trono 0').first);
      expect(find.byType(ExperienceDetailsPage), findsOneWidget);
      expect(
        tester
            .widget<ExperienceDetailsPage>(find.byType(ExperienceDetailsPage))
            .visitId,
        'visit-99',
      );
    },
  );

  testWidgets('sample podium and profile render with diverse identities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    addTearDown(state.dispose);
    for (final dark in [false, true]) {
      await mount(
        tester,
        state,
        const Scaffold(body: RankingsPage()),
        dark: dark,
      );
      expect(find.byType(RankingPodium), findsOneWidget);
      for (var i = 1; i <= 3; i++) {
        expect(find.byKey(ValueKey('podium-$i')), findsOneWidget);
      }
      await capture(tester, 'sample-podium-$dark');
      await tap(tester, find.text('Melhores'));
      expect(find.byType(RankingPodium), findsNothing);
      await mount(
        tester,
        state,
        const Scaffold(body: ProfilePage()),
        dark: dark,
      );
      await capture(tester, 'sample-profile-$dark');
      expect(find.text('Explorador local'), findsOneWidget);
      expect(find.text('Definições'), findsNothing);
      expect(find.text('🧭'), findsNothing);
      expect(find.text('O teu trono habitual'), findsOneWidget);
      expect(find.text('O teu favorito nas avaliações'), findsOneWidget);
      expect(find.textContaining('Média das tuas'), findsOneWidget);
      for (final label in [
        'O teu trono habitual',
        'O teu favorito nas avaliações',
      ]) {
        await tap(tester, find.text(label));
        expect(find.byType(BathroomDetailsPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }
  });

  test('natural diary headings respect calendar boundaries', () {
    expect(
      diaryLabel(DateTime(2026, 1, 1), now: DateTime(2026, 1, 1, 23)),
      'Hoje',
    );
    expect(
      diaryLabel(DateTime(2025, 12, 31), now: DateTime(2026, 1, 1)),
      'Ontem',
    );
  });
  testWidgets('podium handles one, two, three and no ranked bathrooms', (
    tester,
  ) async {
    for (final count in [0, 1, 2, 3]) {
      final state = AppState();
      final ranked = rankBathrooms(
        state.allBathrooms,
        state.reviews,
        RankingMetric.overall,
      ).take(count).toList();
      await mount(
        tester,
        state,
        Scaffold(
          body: RankingPodium(rows: ranked, metric: RankingMetric.overall),
        ),
      );
      for (var i = 1; i <= 3; i++) {
        expect(
          find.byKey(ValueKey('podium-$i')),
          i <= count ? findsOneWidget : findsNothing,
        );
      }
      if (count > 0) {
        await tap(tester, find.text(ranked.first.bathroom.name));
        expect(find.byType(BathroomDetailsPage), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    }
  });

  test('diary date uses the local calendar', () {
    final timestamp = DateTime.utc(2026, 7, 1, 23, 30);
    final local = timestamp.toLocal();
    expect(
      diaryDay(timestamp),
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}',
    );
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'collection rankings profile settings at $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = catalogue();
            addTearDown(state.dispose);
            final semantics = tester.ensureSemantics();
            await mount(
              tester,
              state,
              const Scaffold(body: CollectionPage()),
              dark: dark,
              scale: scale,
            );
            await capture(tester, 'collection-$width-$dark-$scale');
            expect(tester.takeException(), isNull);
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await tap(tester, find.text('Diário'));
            await capture(tester, 'diary-$width-$dark-$scale');
            expect(tester.takeException(), isNull);
            await mount(
              tester,
              state,
              const Scaffold(body: RankingsPage()),
              dark: dark,
              scale: scale,
            );
            expect(find.byType(ChoiceChip), findsNothing);
            expect(find.byType(CircleAvatar), findsNothing);
            await capture(tester, 'rankings-$width-$dark-$scale');
            await tap(tester, find.text('Por categoria'));
            await capture(tester, 'ranking-category-$width-$dark-$scale');
            await tap(tester, find.text('Geral'));
            await tap(tester, find.text('Pessoal'));
            await tap(tester, find.text('Por categoria'));
            await tester.drag(find.byType(TabBar), const Offset(-500, 0));
            await tester.pumpAndSettle();
            await tap(tester, find.text('Papel'));
            expect(find.text('0,0 / 2'), findsOneWidget);
            await tap(tester, find.text('Melhores'));
            expect(find.text('Piores'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await mount(
              tester,
              state,
              const Scaffold(body: ProfilePage()),
              dark: dark,
              scale: scale,
            );
            await capture(tester, 'profile-$width-$dark-$scale');
            expect(tester.takeException(), isNull);
            await mount(
              tester,
              state,
              const SettingsPage(),
              dark: dark,
              scale: scale,
            );
            await capture(tester, 'settings-$width-$dark-$scale');
            await tap(tester, find.text('Modo escuro'));
            expect(state.darkMode, isFalse);
            expect(tester.takeException(), isNull);
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            semantics.dispose();
          },
        );
      }
    }
  }
}
