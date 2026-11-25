import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> mountWizard(
  WidgetTester tester,
  AppState state, {
  ReviewFormPage page = const ReviewFormPage(bathroomId: '5'),
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => page),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await wizardTap(tester, find.text('Abrir'));
}

Future<void> wizardTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> answerDetails(WidgetTester tester) async {
  for (final key in ['Higiene-0', 'Conforto-1', 'Estética-3', 'Papel-2']) {
    await wizardTap(tester, find.byKey(ValueKey(key)));
  }
}

void main() {
  testWidgets(
    'single star strip handles tenths, zero, drag, keyboard and semantics',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final semantics = tester.ensureSemantics();

      await mountWizard(tester, state);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Dar zero'), findsNothing);
      expect(find.bySemanticsLabel('Avaliação global'), findsOneWidget);
      final stars = find.byType(StarRatingInput);
      final rect = tester.getRect(stars);
      await tester.tapAt(Offset(rect.left, rect.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('0,0 / 5'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('0,1 / 5'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text('5,0 / 5'), findsOneWidget);
      expect(find.text('🤩'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text('0,0 / 5'), findsOneWidget);
      await tester.dragFrom(
        Offset(rect.left, rect.center.dy),
        Offset(rect.width * .74, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('3,7 / 5'), findsOneWidget);
      expect(find.text('🙂'), findsOneWidget);
      expect(state.visitsFor('5'), isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'draft survives steps, visit sheet and cancellation; zero saves atomically once',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final visit = state.recordVisit('5', visitedAt: DateTime.utc(2020));
      final before = state.visits.length;
      await mountWizard(tester, state);
      await wizardTap(tester, find.text('Alterar'));
      expect(find.byType(BottomSheet), findsOneWidget);
      await wizardTap(tester, find.text('Acabei de visitar'));
      await tester.tapAt(
        tester.getTopLeft(find.byType(StarRatingInput)) + const Offset(0, 32),
      );
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('Continuar'));
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Procurar etiquetas'),
        'Espelho',
      );
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('🪞 Espelho gigante'));
      await wizardTap(tester, find.text('Voltar'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuar'),
            )
            .onPressed,
        isNotNull,
      );
      await wizardTap(tester, find.text('Voltar'));
      expect(find.text('0,0 / 5'), findsOneWidget);
      expect(find.text('Acabei de visitar'), findsOneWidget);
      await wizardTap(tester, find.text('Alterar'));
      await wizardTap(tester, find.textContaining('Uma visita anterior'));
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      expect(
        find.widgetWithText(InputChip, '🪞 Espelho gigante'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.visits.length, before);
      expect(state.reviewForVisit(visit.id), isNull);
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: '5', visitId: visit.id),
      );
      expect(find.text('Alterar'), findsNothing);
      await tester.tapAt(
        tester.getTopLeft(find.byType(StarRatingInput)) + const Offset(0, 32),
      );
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('Continuar'));
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      var notifications = 0;
      state.addListener(() => notifications++);
      await wizardTap(tester, find.text('Guardar sem etiquetas'));
      expect(notifications, 1);
      expect(state.visits.length, before);
      expect(state.reviewForVisit(visit.id)!.rating, 0);
    },
  );

  testWidgets(
    'tag capability, bounded suggestions, search, duplicate and count errors',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final original = state.reviews.first;
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(
          bathroomId: original.bathroomId,
          review: original,
          canCreateCustomTags: false,
        ),
      );
      expect(find.text('Alterar'), findsNothing);
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      expect(find.text('Inventar uma etiqueta'), findsNothing);
      expect(find.byType(ActionChip).evaluate().length, lessThanOrEqualTo(6));
      await tester.enterText(
        find.widgetWithText(TextField, 'Procurar etiquetas'),
        'espelho',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsOneWidget);
      await wizardTap(tester, find.text('🪞 Espelho gigante'));
      expect(
        find.widgetWithText(InputChip, '🪞 Espelho gigante'),
        findsOneWidget,
      );
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: original.bathroomId, review: original),
      );
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Inventar uma etiqueta'));
      final input = find.widgetWithText(TextField, 'A tua etiqueta');
      for (var i = 0; i < 10 - original.tags.length; i++) {
        await tester.enterText(input, 'personal $i');
        await wizardTap(tester, find.text('Adicionar etiqueta'));
      }
      await tester.enterText(input, 'extra');
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      expect(find.text('Podes adicionar até 10 etiquetas.'), findsOneWidget);
      // Duplicate check after removing an entry so the limit does not mask it.
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'personal 0'))
          .onDeleted!();
      await tester.pumpAndSettle();
      await tester.enterText(input, 'personal 1');
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      expect(find.text('Esta etiqueta já está selecionada.'), findsOneWidget);
      expect(state.reviews.first, same(original));
    },
  );

  testWidgets('new visit and review save once on repeated submission', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    final visits = state.visits.length;
    final reviews = state.reviews.length;
    await mountWizard(tester, state);
    tester.widget<StarRatingInput>(find.byType(StarRatingInput)).onChanged(4.1);
    await tester.pumpAndSettle();
    await wizardTap(tester, find.text('Continuar'));
    await answerDetails(tester);
    await wizardTap(tester, find.text('Continuar'));
    var notifications = 0;
    state.addListener(() => notifications++);
    final save = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Guardar sem etiquetas'),
        )
        .onPressed!;
    save();
    save();
    await tester.pumpAndSettle();
    expect(state.visits.length, visits + 1);
    expect(state.reviews.length, reviews + 1);
    expect(notifications, 1);
    final visit = state.visitsFor('5').single;
    expect(state.reviewForVisit(visit.id)!.rating, 4.1);
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'wizard responsive, accessible and keyboard safe at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = AppState();
          addTearDown(state.dispose);
          final semantics = tester.ensureSemantics();

          await mountWizard(tester, state, dark: dark, scale: 1.5);
          await tester.ensureVisible(find.byType(StarRatingInput));
          await tester.pumpAndSettle();
          await tester.tapAt(tester.getCenter(find.byType(StarRatingInput)));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await wizardTap(tester, find.text('Continuar'));
          await answerDetails(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await wizardTap(tester, find.text('Continuar'));
          await wizardTap(tester, find.text('Inventar uma etiqueta'));
          await tester.enterText(
            find.widgetWithText(TextField, 'A tua etiqueta'),
            'acústica',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await wizardTap(tester, find.text('Adicionar etiqueta'));
          expect(find.widgetWithText(InputChip, 'acústica'), findsOneWidget);
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          semantics.dispose();
        },
      );
    }
  }
}
