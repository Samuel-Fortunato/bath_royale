import 'package:bath_royale/widgets/wc_card.dart';
import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> mount(WidgetTester tester, AppState state, Widget page) =>
      tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: page),
          ),
        ),
      );
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'details navigation, explicit visit, favourite and edit update cards',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await mount(tester, state, const ExplorePage());
      await tester.enterText(find.byType(TextField), 'DEM - 3º piso');
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.descendant(
          of: find.byType(WcCard),
          matching: find.text('DEM - 3º piso'),
        ),
      );
      expect(find.text('Comunidade'), findsOneWidget);
      expect(find.text('Média: 4.7 / 5'), findsOneWidget);
      await tap(tester, find.byTooltip('Adicionar aos favoritos'));
      expect(state.activityFor('0').isFavorite, isTrue);
      await tap(tester, find.text('Registar visita agora'));
      expect(state.activityFor('0').lastVisitedAt!.year, DateTime.now().year);
      await tester.tap(find.text('Desfazer visita'));
      await tester.pumpAndSettle();
      expect(
        state.activityFor('0').lastVisitedAt,
        state.reviews.first.createdAt,
      );
      expect(state.activityFor('0').isFavorite, isTrue);
      await tap(tester, find.text('Registar visita agora'));
      await tap(tester, find.text('Agora não'));
      await tap(tester, find.text('Editar avaliação'));
      tester.widget<Slider>(find.byType(Slider)).onChanged!(2.5);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Guardar avaliação'));
      expect(state.reviews.length, 5);
      expect(state.entries.first.personalReview!.rating, 2.5);
      await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('Média: 2.5 / 5'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2.5'), findsOneWidget);
    },
  );
  testWidgets('new review validates fields and saves repeat experience', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    final visit = state.recordVisit('0', visitedAt: DateTime.utc(2027));
    await mount(tester, state, const ExplorePage());
    await tester.enterText(find.byType(TextField), 'DEM - 3º piso');
    await tester.pumpAndSettle();
    await tap(
      tester,
      find.descendant(
        of: find.byType(WcCard),
        matching: find.text('DEM - 3º piso'),
      ),
    );
    await tap(tester, find.text('Nova avaliação'));
    await tap(tester, find.text('Guardar avaliação'));
    expect(find.text('Escolhe uma opção'), findsNWidgets(4));
    expect(state.reviews.length, 5);
    expect(find.text('Escolhe uma avaliação'), findsOneWidget);
    await tester.ensureVisible(find.byType(RatingBar));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byType(RatingBar)) + const Offset(100, 18),
    );
    await tester.pumpAndSettle();
    expect(find.text('Escolhe'), findsNothing);
    await tap(tester, find.text('Dar zero'));
    expect(find.text('💀 0.0 / 5'), findsOneWidget);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(4.5);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      final dropdown = find.byType(DropdownButtonFormField<int>).at(i);
      await tap(tester, dropdown);
      await tester.tap(
        find
            .text(
              [
                '✨ Um brinco',
                '🛋️ Poltrona',
                '🌈 Scenic piss',
                '🧻 Suficiente',
              ][i],
            )
            .last,
      );
      await tester.pumpAndSettle();
    }
    await tap(tester, find.text('🪞 Espelho gigante'));
    await tap(tester, find.text('Inventar uma etiqueta'));
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'A tua etiqueta'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'A tua etiqueta'),
      'vista',
    );
    await tap(tester, find.byTooltip('Adicionar etiqueta'));
    await tap(tester, find.text('Guardar avaliação'));
    expect(state.reviews.length, 6);
    expect(state.visits.length, 6);
    expect(state.entries.first.personalReview!.visitId, visit.id);
    expect(state.entries.first.personalReview!.tags, [
      '🪞 Espelho gigante',
      'vista',
    ]);
    expect(state.entries.first.reviewCount, 2);
    expect(find.byType(ReviewFormPage), findsNothing);
  });
  testWidgets('cancelling a review leaves state untouched on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    addTearDown(state.dispose);
    await mount(tester, state, const ExplorePage());
    await tester.enterText(find.byType(TextField), 'DEM - 3º piso');
    await tester.pumpAndSettle();
    await tap(
      tester,
      find.descendant(
        of: find.byType(WcCard),
        matching: find.text('DEM - 3º piso'),
      ),
    );
    await tap(tester, find.text('Nova avaliação'));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(state.reviews.length, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editing retains precise rating and supports removing custom tags',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final original = state.reviews.first;
      await mount(
        tester,
        state,
        ReviewFormPage(bathroomId: original.bathroomId, review: original),
      );
      expect(find.textContaining('4.7 / 5'), findsOneWidget);
      await tap(tester, find.text('Inventar uma etiqueta'));
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'A tua etiqueta'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'A tua etiqueta'),
        'sossegado',
      );
      await tap(tester, find.byTooltip('Adicionar etiqueta'));
      expect(find.text('sossegado'), findsOneWidget);
      final chip = tester.widget<InputChip>(
        find.widgetWithText(InputChip, 'sossegado'),
      );
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(find.text('sossegado'), findsNothing);
      await tap(tester, find.text('Guardar avaliação'));
      expect(state.reviews.first.rating, original.rating);
      expect(state.reviews.first.tags, original.tags);
    },
  );

  testWidgets(
    'visit invitation can be dismissed and history deletion is confirmed',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await mount(tester, state, const ExplorePage());
      await tester.enterText(find.byType(TextField), 'Nome de Teste');
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.descendant(
          of: find.byType(WcCard),
          matching: find.text('Nome de Teste'),
        ),
      );
      await tap(tester, find.text('Registar visita agora'));
      expect(state.visitsFor('5').length, 1);
      await tap(tester, find.text('Avaliar esta visita'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.visitsFor('5').length, 1);
      expect(state.reviewForVisit(state.visitsFor('5').single.id), isNull);
      await tap(tester, find.byTooltip('Avaliar visita'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Remover visita'));
      await tap(tester, find.text('Cancelar'));
      expect(state.visitsFor('5').length, 1);
      await tap(tester, find.byTooltip('Remover visita'));
      await tap(tester, find.text('Remover'));
      expect(state.visitsFor('5'), isEmpty);
    },
  );

  testWidgets(
    'removing a reviewed visit warns and removes its review only after confirmation',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await mount(tester, state, const ExplorePage());
      await tester.enterText(find.byType(TextField), 'DEM - 3º piso');
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.descendant(
          of: find.byType(WcCard),
          matching: find.text('DEM - 3º piso'),
        ),
      );
      await tap(tester, find.byTooltip('Remover visita'));
      expect(
        find.text('A avaliação associada também será removida.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancelar'));
      expect(state.reviews.length, 5);
      await tap(tester, find.byTooltip('Remover visita'));
      await tap(tester, find.text('Remover'));
      expect(state.reviews.length, 4);
      expect(state.visitsFor('0'), isEmpty);
    },
  );

  testWidgets(
    'unfinished hidden tag is revealed with a visible error and can be resolved',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final original = state.reviews.first;
      await mount(
        tester,
        state,
        ReviewFormPage(bathroomId: original.bathroomId, review: original),
      );
      await tap(tester, find.text('Inventar uma etiqueta'));
      await tester.enterText(
        find.widgetWithText(TextField, 'A tua etiqueta'),
        'rascunho',
      );
      await tap(tester, find.text('Inventar uma etiqueta'));
      expect(find.widgetWithText(TextField, 'A tua etiqueta'), findsNothing);
      await tap(tester, find.text('Guardar avaliação'));
      expect(
        find.text('Adiciona ou apaga a etiqueta antes de guardar.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'A tua etiqueta'), findsOneWidget);
      expect(state.reviews.first, same(original));
      await tester.enterText(
        find.widgetWithText(TextField, 'A tua etiqueta'),
        '',
      );
      await tap(tester, find.text('Guardar avaliação'));
      expect(state.reviews.first.tags, original.tags);
    },
  );
  testWidgets('another author cannot edit a review', (tester) async {
    final state = AppState(currentUserId: 'visitor');
    addTearDown(state.dispose);
    await mount(
      tester,
      state,
      ReviewFormPage(bathroomId: '0', review: state.reviews.first),
    );
    expect(find.text('Só podes editar as tuas avaliações.'), findsOneWidget);
    expect(find.text('Guardar avaliação'), findsNothing);
  });
}
