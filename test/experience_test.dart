import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/pages/bathroom_details.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/pages/experience_details.dart';
import 'package:bath_royale/pages/bathroom_form.dart';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/widgets/bathroom_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'review_wizard_test.dart' show wizardTap, answerDetails;

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_S4')) return;
    for (final item in [
      ('Roboto', const String.fromEnvironment('S4_FONT')),
      ('Noto Color Emoji', const String.fromEnvironment('S4_EMOJI')),
    ]) {
      final bytes = await File(item.$2).readAsBytes();
      await (FontLoader(
        item.$1,
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });
  testWidgets(
    'experience navigation from history and ownership-aware actions',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: BathroomDetailsPage(bathroomId: '0')),
        ),
      );
      await wizardTap(tester, find.text('Visitas'));
      await wizardTap(tester, find.text('4,7 / 5'));
      expect(find.byType(ExperienceDetailsPage), findsOneWidget);
      expect(find.text('Editar avaliação'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final foreign = AppState(
        visits: [
          Visit(
            id: 'foreign',
            bathroomId: '5',
            userId: 'other',
            visitedAt: DateTime.utc(2020),
          ),
        ],
        reviews: [],
      );
      addTearDown(foreign.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: foreign,
          child: const MaterialApp(
            home: ExperienceDetailsPage(visitId: 'foreign'),
          ),
        ),
      );
      expect(find.text('Visita registada'), findsOneWidget);
      expect(find.text('Avaliar visita'), findsNothing);
      expect(find.text('Remover visita'), findsNothing);
    },
  );

  testWidgets('legacy tag decoration never mutates or duplicates stored text', (
    tester,
  ) async {
    for (final tag in ['cozy', '🎨 grafiti', 'unknown', 'misto 🧪']) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ReviewTag(tag))),
      );
      expect(find.text(tag), findsOneWidget);
      expect(find.text('🎨 🎨 grafiti'), findsNothing);
      if (tag == 'unknown' || tag == 'misto 🧪') {
        expect(find.text('🏷️'), findsOneWidget);
      }
      if (tag == 'cozy') expect(find.text('🛋️'), findsOneWidget);
    }
  });
  testWidgets(
    'specific experience creates and edits its review and confirms removal',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final visit = state.recordVisit('5', visitedAt: DateTime.utc(2020));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(home: ExperienceDetailsPage(visitId: visit.id)),
        ),
      );
      expect(find.text('Visita registada'), findsOneWidget);
      await wizardTap(tester, find.text('Avaliar visita'));
      tester.widget<StarRatingInput>(find.byType(StarRatingInput)).onChanged(0);
      await tester.pump();
      await wizardTap(tester, find.text('Continuar'));
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Guardar sem etiquetas'));
      expect(state.visitsFor('5').single.id, visit.id);
      expect(state.reviewForVisit(visit.id)!.rating, 0);
      final original = state.reviewForVisit(visit.id)!;
      await wizardTap(tester, find.text('Editar avaliação'));
      tester.widget<StarRatingInput>(find.byType(StarRatingInput)).onChanged(4);
      await tester.pump();
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Guardar sem etiquetas'));
      expect(state.reviewForVisit(visit.id)!.id, original.id);
      expect(state.reviewForVisit(visit.id)!.rating, 4);
      await wizardTap(tester, find.text('Remover visita'));
      expect(
        find.text('A avaliação associada também será removida.'),
        findsOneWidget,
      );
      await wizardTap(tester, find.text('Cancelar'));
      expect(state.reviewForVisit(visit.id), isNotNull);
      await wizardTap(tester, find.text('Remover visita'));
      await wizardTap(tester, find.text('Remover'));
      expect(state.visitsFor('5'), isEmpty);
      expect(state.reviewForVisit(visit.id), isNull);
    },
  );
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 1200.0]) {
      testWidgets('identity creation and experience layout $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        addTearDown(state.dispose);
        Future<void> mount(Widget page) => tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: page,
            ),
          ),
        );
        await mount(const BathroomFormPage());
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Novo trono real');
        await tester.scrollUntilVisible(
          find.text('Surpreende-me'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await wizardTap(tester, find.text('Surpreende-me'));
        await tester.drag(find.byType(ListView), const Offset(0, 1200));
        await tester.pumpAndSettle();
        final preview = tester.widget<BathroomIdentity>(
          find.byType(BathroomIdentity),
        );
        expect(
          preview.bathroom.emoji,
          isIn(['🚽', '👑', '📚', '🌿', '🔧', '🌈', '🏛️', '🧪']),
        );
        final randomized = preview.bathroom.emoji;
        await tester.enterText(find.byType(TextFormField), 'Novo trono real');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BathroomIdentity>(find.byType(BathroomIdentity))
              .bathroom
              .emoji,
          randomized,
        );
        await wizardTap(tester, find.widgetWithText(ChoiceChip, '👑'));
        await wizardTap(tester, find.widgetWithText(ChoiceChip, 'Rosa'));
        await wizardTap(tester, find.text('Criar casa de banho'));
        expect(state.allBathrooms.last.emoji, '👑');
        expect(state.allBathrooms.last.accent, 4);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await mount(const ExperienceDetailsPage(visitId: 'visit-0'));
        await tester.pumpAndSettle();
        expect(find.byType(BathroomIdentity), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  if (const bool.fromEnvironment('CAPTURE_S4')) {
    for (final dark in [false, true]) {
      testWidgets('render Session 4A dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        addTearDown(state.dispose);
        for (final item in <(String, Widget)>[
          ('explore', const Scaffold(body: ExplorePage())),
          ('details', const BathroomDetailsPage(bathroomId: '0')),
          ('experience', const ExperienceDetailsPage(visitId: 'visit-0')),
          ('creation', const BathroomFormPage()),
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: state,
              child: MaterialApp(
                theme: (dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                    .copyWith(
                      textTheme:
                          (dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                              .textTheme
                              .apply(
                                fontFamilyFallback: const ['Noto Color Emoji'],
                              ),
                    ),
                home: RepaintBoundary(child: item.$2),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/s4-${item.$1}-$dark.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
