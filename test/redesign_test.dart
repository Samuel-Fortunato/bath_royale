import 'package:bath_royale/models/bathroom_descriptions.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/pages/bathroom_details.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> mount(
  WidgetTester tester,
  AppState state,
  Widget page, {
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'contextual shell retains Explore state and exposes theme in settings',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await mount(tester, state, const HomePage());
      expect(find.widgetWithText(AppBar, 'Explorar'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsNothing);
      await tester.enterText(find.byType(TextField), 'DEM');
      await tap(tester, find.text('Perfil'));
      expect(find.widgetWithText(AppBar, 'Perfil'), findsOneWidget);
      expect(find.text('Definições'), findsNothing);
      expect(find.byTooltip('Definições'), findsOneWidget);
      await tap(tester, find.byTooltip('Definições'));
      final original = state.darkMode;
      await tap(tester, find.text('Modo escuro'));
      expect(state.darkMode, !original);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Explorar'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'DEM',
      );
      expect(find.byTooltip('Criar casa de banho'), findsOneWidget);
    },
  );

  testWidgets(
    'single filter entry, personal section, discovery independent of reviews and reset',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      state.recordVisit('5', visitedAt: DateTime.utc(2030));
      await mount(tester, state, const HomePage());
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('♥ Favoritos'), findsNothing);
      await tap(tester, find.byTooltip('Filtros'));
      await tap(tester, find.text('Os meus tronos'));
      await tap(tester, find.text('Visitadas'));
      await tap(tester, find.text('Sem avaliações'));
      await tap(tester, find.text('Ver resultados'));
      expect(find.text('Nome de Teste'), findsOneWidget);
      expect(find.text('1 resultados'), findsOneWidget);
      expect(find.text('✓ Descoberta'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      expect(
        tester.widget<Badge>(find.byType(Badge)).label,
        isA<Text>().having((t) => t.data, 'count', '2'),
      );
      await tap(tester, find.byTooltip('Filtros'));
      await tap(tester, find.text('Os meus tronos'));
      await tap(tester, find.text('Por descobrir'));
      await tap(tester, find.text('Ver resultados'));
      expect(find.textContaining('Nenhum trono à vista'), findsOneWidget);
      expect(find.text('Visitadas'), findsNothing);
      await tap(tester, find.byTooltip('Filtros'));
      await tap(tester, find.text('Os meus tronos'));
      await tap(tester, find.text('Por descobrir'));
      await tap(tester, find.text('Ver resultados'));
      expect(find.text('Nome de Teste'), findsOneWidget);
      await tap(tester, find.text('Limpar pesquisa e filtros'));
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('6 resultados'), findsNothing);
    },
  );

  testWidgets(
    'summary uses numeric community means and latest reviewed visit, not latest submission',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final old = state.recordVisit('0', visitedAt: DateTime.utc(2020));
      state.saveReview(
        Review(
          id: 'late-review',
          visitId: old.id,
          bathroomId: '0',
          authorId: state.currentUserId,
          createdAt: DateTime.utc(2030),
          rating: 0,
          hygiene: 1,
          comfort: 0,
          aesthetics: 0,
          paperAvailability: 0,
        ),
      );
      await mount(tester, state, const BathroomDetailsPage(bathroomId: '0'));
      expect(find.text('2,4 / 5'), findsOneWidget);
      expect(
        find.text('2 avaliações da comunidade · média das avaliações locais'),
        findsOneWidget,
      );
      expect(find.text('2,5 / 4'), findsOneWidget);
      expect(find.text('1,0 / 2'), findsOneWidget);
      expect(find.textContaining('Um brinco'), findsNothing);
      await tap(tester, find.text('A tua experiência'));
      expect(find.text('4,7 / 5'), findsOneWidget);
      expect(
        find.text(state.entries.first.personalReview!.hygieneText),
        findsOneWidget,
      );
      expect(
        find.textContaining('Última experiência avaliada ·'),
        findsOneWidget,
      );
      await tap(tester, find.text('Avaliações'));
      expect(
        find.text('Criada: ${reviewDate(DateTime.utc(2030))}'),
        findsOneWidget,
      );
      expect(find.textContaining('média das avaliações locais'), findsNothing);
      await tap(tester, find.text('Resumo'));
      expect(find.text('4,7 / 5'), findsOneWidget);
    },
  );

  testWidgets(
    'close, back and swipe preserve visits; undo is separate and targets exact visit',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      state.toggleFavorite('5');
      await mount(tester, state, const BathroomDetailsPage(bathroomId: '5'));
      await tap(tester, find.text('Estive aqui!'));
      final first = state.visitsFor('5').single;
      expect(
        tester.getCenter(find.text('Desfazer')).dx,
        lessThan(tester.getCenter(find.byTooltip('Fechar convite')).dx - 48),
      );
      await tap(tester, find.byTooltip('Fechar convite'));
      expect(state.visitsFor('5').single.id, first.id);
      // Expire the real-time duplicate guard before deliberately recording another visit.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 850)),
      );
      await tap(tester, find.text('Estive aqui!'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(state.visitsFor('5').length, 2);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 850)),
      );
      await tap(tester, find.text('Estive aqui!'));
      await tester.drag(find.byType(BottomSheet), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(state.visitsFor('5').length, 3);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 850)),
      );
      await tap(tester, find.text('Estive aqui!'));
      final unrelated = state.recordVisit('5', visitedAt: DateTime.utc(2040));
      await tap(tester, find.text('Desfazer'));
      expect(state.visitsFor('5').length, 4);
      expect(state.visits.any((v) => v.id == unrelated.id), isTrue);
      expect(state.visits.any((v) => v.id == first.id), isTrue);
      expect(state.activityFor('5').isFavorite, isTrue);
    },
  );

  testWidgets(
    'long histories are lazy, independent and retain their scroll positions',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      for (var i = 0; i < 100; i++) {
        final visit = state.recordVisit(
          '5',
          visitedAt: DateTime.utc(2020, 1, i + 1),
        );
        state.saveReview(
          Review(
            id: 'review-$i',
            visitId: visit.id,
            bathroomId: '5',
            authorId: state.currentUserId,
            createdAt: visit.visitedAt,
            rating: 0,
            hygiene: 0,
            comfort: 0,
            aesthetics: 0,
            paperAvailability: 0,
          ),
        );
      }
      await mount(tester, state, const BathroomDetailsPage(bathroomId: '5'));
      expect(find.text('0,0 / 5'), findsOneWidget);
      await tap(tester, find.text('Avaliações'));
      expect(find.text('Editar avaliação').evaluate().length, lessThan(10));
      await tester.drag(find.byType(ListView).last, const Offset(0, -800));
      await tester.pumpAndSettle();
      final reviewPosition = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      expect(reviewPosition, greaterThan(0));
      await tap(tester, find.text('Visitas'));
      expect(find.byTooltip('Remover visita').evaluate().length, lessThan(20));
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        0,
      );
      await tap(tester, find.text('Avaliações'));
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        reviewPosition,
      );
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('responsive accessible shell/details at $width, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        addTearDown(state.dispose);
        final semantics = tester.ensureSemantics();
        await mount(tester, state, const HomePage(), dark: dark, scale: 1.5);
        await tap(tester, find.byTooltip('Filtros'));
        await tap(tester, find.text('Ver resultados'));
        await tester.enterText(find.byType(TextField), 'DEM - 3º piso');
        await tester.pumpAndSettle();
        await tap(tester, find.text('DEM - 3º piso').last);
        expect(find.byType(BathroomDetailsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await tap(tester, find.text('A tua experiência'));
        await tap(tester, find.text('Avaliações'));
        await tap(tester, find.text('Visitas'));
        await tap(tester, find.text('Estive aqui!'));
        await tap(tester, find.text('Agora não'));
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
