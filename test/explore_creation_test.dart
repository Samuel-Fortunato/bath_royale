import 'package:bath_royale/models/bathroom_sort.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'creation validates, prevents duplicates and keeps records separate',
    () {
      final state = AppState(bathrooms: []);
      addTearDown(state.dispose);
      var notifications = 0;
      state.addListener(() => notifications++);
      expect(() => state.createBathroom('  '), throwsArgumentError);
      expect(() => state.createBathroom('a' * 101), throwsArgumentError);
      final bathroom = state.createBathroom('  Novo   Trono  ');
      expect(bathroom.name, 'Novo Trono');
      expect(bathroom.createdBy, state.currentUserId);
      expect(() => state.createBathroom('novo trono'), throwsArgumentError);
      expect(notifications, 1);
      expect(state.entries.single.personalReview, isNull);
      expect(state.entries.single.communityRating, isNull);
      expect(state.activityFor(bathroom.id).lastVisitedAt, isNull);
      expect(() => state.allBathrooms.clear(), throwsUnsupportedError);
    },
  );

  test(
    'sorts descending, puts missing values last and uses explicit visits',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      final fresh = state.createBathroom('AAA');
      expect(
        sortBathrooms(state.entries, BathroomSort.name).first.bathroom.id,
        fresh.id,
      );
      for (final sort in [BathroomSort.community, BathroomSort.personal]) {
        final entries = sortBathrooms(state.entries, sort);
        expect(entries.first.personalReview!.rating, 4.7);
        expect(entries.last.personalReview, isNull);
      }
      state.recordVisit(fresh.id, visitedAt: DateTime.utc(2030));
      expect(
        sortBathrooms(
          state.entries,
          BathroomSort.latestVisit,
        ).first.bathroom.id,
        fresh.id,
      );
    },
  );

  testWidgets('collection follows explicit visit creation and removal', (
    tester,
  ) async {
    final state = AppState(bathrooms: []);
    addTearDown(state.dispose);
    final bathroom = state.createBathroom('Trono novo');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: AppTheme.lightTheme, home: const HomePage()),
      ),
    );
    await tester.tap(find.text('Coleção'));
    await tester.pumpAndSettle();
    expect(find.textContaining('que visitares'), findsOneWidget);
    final visit = state.recordVisit(bathroom.id, visitedAt: DateTime.utc(2026));
    await tester.pumpAndSettle();
    expect(find.text('Trono novo'), findsNWidgets(2));
    expect(find.text('1 visita'), findsOneWidget);
    state.deleteVisit(visit.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('que visitares'), findsOneWidget);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('creation, duplicate validation, search and reset at $width', (
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
            home: const HomePage(),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Criar casa de banho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar casa de banho'));
      await tester.pumpAndSettle();
      expect(find.text('Dá um nome a este trono.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'dem - 3º piso');
      await tester.tap(find.text('Criar casa de banho'));
      await tester.pumpAndSettle();
      expect(
        find.text('Já existe uma casa de banho com este nome.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'Novo trono');
      await tester.tap(find.text('Criar casa de banho'));
      await tester.pumpAndSettle();
      expect(state.allBathrooms.length, 7);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ordenar por'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Última visita (mais recente)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🛋️ Confortável'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      expect(find.text('🛋️ Confortável'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhum trono à vista'), findsOneWidget);
      await tester.tap(find.text('Limpar pesquisa e filtros'));
      await tester.pumpAndSettle();
      expect(find.text('7 casas de banho'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
