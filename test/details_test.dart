import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
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
      await tap(tester, find.text('DEM - 3º piso'));
      expect(find.text('Comunidade'), findsOneWidget);
      expect(find.text('Média: 4.7 / 5'), findsOneWidget);
      await tap(tester, find.byTooltip('Adicionar aos favoritos'));
      expect(state.activityFor('0').isFavorite, isTrue);
      await tap(tester, find.text('Registar visita agora'));
      expect(state.activityFor('0').lastVisitedAt!.year, DateTime.now().year);
      await tap(tester, find.text('Editar avaliação'));
      await tester.enterText(find.byType(TextFormField).first, '2,5');
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
    await mount(tester, state, const ExplorePage());
    await tap(tester, find.text('DEM - 3º piso'));
    await tap(tester, find.text('Nova avaliação'));
    await tap(tester, find.text('Guardar avaliação'));
    expect(find.text('Escolhe uma opção'), findsNWidgets(4));
    expect(state.reviews.length, 5);
    await tester.enterText(find.byType(TextFormField).first, 'NaN');
    await tap(tester, find.text('Guardar avaliação'));
    await tester.ensureVisible(find.byType(TextFormField).first);
    expect(find.text('Indica um número entre 0 e 5'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '4,5');
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
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, 'limpo,,vista');
    await tap(tester, find.text('Guardar avaliação'));
    expect(state.reviews.length, 5);
    await tester.enterText(
      find.byType(TextFormField).last,
      'limpo, vista, limpo',
    );
    await tap(tester, find.text('Guardar avaliação'));
    expect(state.reviews.length, 6);
    expect(state.entries.first.personalReview!.tags, ['limpo', 'vista']);
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
    await tap(tester, find.text('DEM - 3º piso'));
    await tap(tester, find.text('Nova avaliação'));
    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(state.reviews.length, 5);
    expect(tester.takeException(), isNull);
  });
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
