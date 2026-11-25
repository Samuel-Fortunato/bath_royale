import 'dart:io';
import 'dart:ui' as ui;
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
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
      expect(find.textContaining('Trono 0'), findsNothing);
      await tap(tester, find.text('Os meus favoritos'));
      expect(find.byType(FavouritesList), findsOneWidget);
      await tap(tester, find.textContaining('Trono 1'));
      expect(find.byType(BathroomDetailsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Histórico de atividade'));
      expect(find.byType(VisitDiary), findsOneWidget);
      await tap(tester, find.textContaining('Trono 0').first);
      expect(find.byType(BathroomDetailsPage), findsOneWidget);
    },
  );

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
            await tap(tester, find.text('Pessoal'));
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
