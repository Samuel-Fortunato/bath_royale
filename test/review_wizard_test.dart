import 'dart:io';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/tag_presentation.dart';
import 'collection_profile_test.dart' show capture;
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

  test(
    'central tag presentation preserves prefixes and matches legacy aliases',
    () {
      for (final tag in [
        'Nice',
        'Cozy',
        'Dark',
        'Graffiti',
        'Small',
        'Great view',
        'wtf',
        'no like',
        'sad but true',
      ]) {
        final shown = TagPresentation.display(tag);
        expect(TagPresentation.hasEmoji(shown), isTrue);
        expect(TagPresentation.display(shown), shown);
        expect(TagPresentation.key(shown), TagPresentation.key(tag));
      }
      expect(
        TagPresentation.key('🎨 Graffiti'),
        TagPresentation.key('grafiti'),
      );
      expect(TagPresentation.display('unknown'), '🏷️ unknown');
    },
  );

  testWidgets(
    'legacy selected chips, search deduplication, custom validation and removal',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final old = state.reviews.first;
      final legacy = Review(
        id: old.id,
        visitId: old.visitId,
        bathroomId: old.bathroomId,
        authorId: old.authorId,
        createdAt: old.createdAt,
        rating: old.rating,
        paperAvailability: old.paperAvailability,
        hygiene: old.hygiene,
        comfort: old.comfort,
        aesthetics: old.aesthetics,
        tags: ['Nice'],
      );
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: old.bathroomId, review: legacy),
      );
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      expect(
        tester.widget<InputChip>(find.widgetWithText(InputChip, 'Nice')).avatar,
        isA<Text>(),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Procurar etiquetas'),
        'nice',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing);
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'Nice'))
          .onDeleted!();
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsOneWidget);
      await wizardTap(tester, find.byType(ActionChip));
      await wizardTap(tester, find.text('Inventar uma etiqueta'));
      await tester.enterText(
        find.widgetWithText(TextField, 'A tua etiqueta'),
        'nice',
      );
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      expect(find.text('Esta etiqueta já está selecionada.'), findsOneWidget);
      expect(legacy.tags, ['Nice']);
    },
  );

  testWidgets(
    'discrete scales preserve unanswered, zero, keyboard, drag and saved values',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await mountWizard(tester, state);
      tester.widget<StarRatingInput>(find.byType(StarRatingInput)).onChanged(0);
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('Continuar'));
      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('Higiene-slider')))
            .getSemanticsData()
            .value,
        'Por responder',
      );
      expect(find.text('Por responder'), findsNWidgets(4));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuar'),
            )
            .onPressed,
        isNull,
      );
      await wizardTap(tester, find.byKey(const ValueKey('Higiene-0')));
      expect(find.text('Tudo cagado'), findsOneWidget);
      expect(find.text('Por responder'), findsNWidgets(3));
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('Higiene-slider')))
            .getSemanticsData()
            .value,
        '💩 Tudo cagado',
      );
      final hygiene = find.byKey(const ValueKey('Higiene-slider'));
      await wizardTap(tester, hygiene);
      tester.widget<Slider>(hygiene).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text('Um brinco'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text('Tudo cagado'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Sujo'), findsOneWidget);
      final rect = tester.getRect(hygiene);
      await tester.dragFrom(
        Offset(rect.left, rect.center.dy),
        Offset(rect.width, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Um brinco'), findsOneWidget);
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Guardar sem etiquetas'));
      final review = state.reviews.last;
      expect(review.hygiene, 0);
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: review.bathroomId, review: review),
      );
      await wizardTap(tester, find.text('Continuar'));
      expect(find.text('Tudo cagado'), findsOneWidget);
      expect(find.text('Por responder'), findsNothing);
      expect(tester.widget<Slider>(hygiene).value, 0);
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('Papel-slider'))).value,
        2,
      );
      semantics.dispose();
    },
  );

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
    'draft survives steps, system back and confirmed cancellation; zero saves atomically once',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final visit = state.recordVisit('5', visitedAt: DateTime.utc(2020));
      final before = state.visits.length;
      await mountWizard(tester, state);
      expect(find.text('Alterar'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
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
      expect(find.text('Alterar'), findsNothing);
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      expect(
        find.widgetWithText(InputChip, '🪞 Espelho gigante'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Os pequenos detalhes'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('0,0 / 5'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Descartar avaliação?'), findsOneWidget);
      await wizardTap(tester, find.text('Continuar a avaliar'));
      expect(find.text('0,0 / 5'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('Descartar'));
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

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('normal phone emoji scale at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        addTearDown(state.dispose);
        await mountWizard(tester, state, dark: dark);
        tester
            .widget<StarRatingInput>(find.byType(StarRatingInput))
            .onChanged(4);
        await tester.pumpAndSettle();
        await wizardTap(tester, find.text('Continuar'));
        await answerDetails(tester);
        await capture(tester, 'scales-$width-$dark-1.0');
        expect(tester.takeException(), isNull);
      });
    }
  }
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
          await capture(tester, 'scales-unanswered-$width-$dark');
          for (final label in ['Higiene', 'Conforto', 'Estética', 'Papel']) {
            expect(
              tester.getSize(find.byKey(ValueKey('$label-slider'))).height,
              greaterThanOrEqualTo(48),
            );
            expect(
              tester.getSize(find.byKey(ValueKey('$label-0'))).shortestSide,
              greaterThanOrEqualTo(48),
            );
          }
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await answerDetails(tester);
          await capture(tester, 'scales-$width-$dark-1.5');
          await tester.ensureVisible(find.byKey(const ValueKey('Higiene-0')));
          await tester.pumpAndSettle();
          await capture(tester, 'scales-top-$width-$dark');
          for (final category in ['Higiene', 'Conforto', 'Estética', 'Papel']) {
            final maximum = category == 'Papel' ? 2 : 4;
            final first = tester.getCenter(find.byKey(ValueKey('$category-0')));
            final last = tester.getCenter(
              find.byKey(ValueKey('$category-$maximum')),
            );
            final track = tester.getRect(
              find.byKey(ValueKey('$category-slider')),
            );
            expect(first.dy, last.dy);
            expect(track.left, closeTo(first.dx, .01));
            expect(track.right, closeTo(last.dx, .01));
          }
          // Measure targets without treating partially scrolled buttons as undersized.
          for (final label in ['Higiene', 'Conforto', 'Estética', 'Papel']) {
            for (var i = 0; i <= (label == 'Papel' ? 2 : 4); i++) {
              expect(
                tester.getSize(find.byKey(ValueKey('$label-$i'))).shortestSide,
                greaterThanOrEqualTo(48),
              );
            }
          }
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await wizardTap(tester, find.text('Continuar'));
          await capture(tester, 'tags-$width-$dark-1.5');
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
