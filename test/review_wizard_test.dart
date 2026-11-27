import 'package:bath_royale/models/content_suggestions.dart';
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
      child: RepaintBoundary(
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
  test(
    'approved content has 40 valid tags/emojis and 18 independent RGB swatches',
    () {
      expect(reviewTagSuggestions.length, 40);
      expect(reviewTagSuggestions.map(TagPresentation.key).toSet().length, 40);
      expect(reviewTagSuggestions.first.label, 'Trono real');
      expect(reviewTagSuggestions.last.label, 'Puzzle de fechaduras');
      expect(bathroomEmojiSuggestions.length, 40);
      expect(bathroomEmojiSuggestions.toSet().length, 40);
      expect(bathroomEmojiSuggestions.every(ReviewTagData.validEmoji), isTrue);
      expect(bathroomColorSuggestions.length, 18);
    },
  );
  testWidgets(
    'six draft tags remain stable through rebuild/search and custom emoji refresh',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final old = state.reviews.first;
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: old.bathroomId, review: old),
      );
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      List<String> suggestions() => tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((c) => (c.label as Text).data!)
          .toList();
      final initial = suggestions();
      expect(initial.length, 6);
      await tester.enterText(
        find.widgetWithText(TextField, 'Comentário (opcional)'),
        'Rebuild',
      );
      await tester.pumpAndSettle();
      expect(suggestions(), initial);
      await tester.enterText(
        find.widgetWithText(TextField, 'Procurar etiquetas'),
        'Puzzle',
      );
      await tester.pumpAndSettle();
      expect(suggestions(), ['Puzzle de fechaduras']);
      await tester.enterText(
        find.widgetWithText(TextField, 'Procurar etiquetas'),
        '',
      );
      await tester.pumpAndSettle();
      expect(suggestions(), initial);
      await wizardTap(tester, find.text('+ Criar etiqueta'));
      final emojiField = find.widgetWithText(TextFormField, 'Emoji');
      await tester.enterText(emojiField, '🇵🇹');
      final emojiButtons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .where((b) => (b.tooltip ?? '').startsWith('Escolher '));
      expect(emojiButtons.length, 8);
      await wizardTap(tester, find.byTooltip('Outros emojis'));
      expect(tester.widget<TextFormField>(emojiField).controller!.text, '🇵🇹');
      await wizardTap(tester, find.text('Cancelar'));
      expect(suggestions(), initial);
    },
  );

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
    'structured tags validate sequences and normalize label equivalence',
    () {
      for (final emoji in [
        '↔️',
        '◀️',
        '⬛',
        '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
        '🫱🏽‍🫲🏻',
        '👩🏽‍💻',
        '👨‍👩‍👧‍👦',
        '🇵🇹',
        '1️⃣',
        '❤️',
        '🧻',
      ]) {
        expect(ReviewTagData.validEmoji(emoji), isTrue, reason: emoji);
        final tag = ReviewTagData(emoji: emoji, label: '  Bom   Trono  ');
        expect(tag.label, 'Bom Trono');
        expect(TagPresentation.key(tag), 'bom trono');
        expect(ReviewTagData.fromJson(tag.toJson()), tag);
      }
      for (final emoji in ['', 'a', 'ab', '😀😀', '🏽', '🇵', '1']) {
        expect(ReviewTagData.validEmoji(emoji), isFalse, reason: emoji);
      }
      expect(
        TagPresentation.key(ReviewTagData(emoji: '👑', label: 'GRAFITI')),
        TagPresentation.key(ReviewTagData(emoji: '🎨', label: 'graffiti')),
      );
      expect(() => ReviewTagData(emoji: 'x', label: 'ok'), throwsArgumentError);
      expect(
        () => ReviewTagData(emoji: '👑', label: 'a' * 31),
        throwsArgumentError,
      );
    },
  );

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
    'five direct stars distinguish unanswered and preserve draft and exit behavior',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final visits = state.visits.length;
      await mountWizard(tester, state);
      expect(find.byType(Slider), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuar'),
            )
            .onPressed,
        isNull,
      );
      final semantics = tester.ensureSemantics();

      for (var i = 1; i <= 5; i++) {
        await wizardTap(tester, find.byKey(ValueKey('global-star-$i')));
        expect(
          tester.widget<StarRatingInput>(find.byType(StarRatingInput)).value,
          i.toDouble(),
        );
      }
      await wizardTap(tester, find.text('Continuar'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuar'),
            )
            .onPressed,
        isNull,
      );
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      final comment = find.widgetWithText(TextField, 'Comentário (opcional)');
      await tester.enterText(comment, 'Uma pausa.');
      await wizardTap(tester, find.text('Voltar'));
      await wizardTap(tester, find.text('Voltar'));
      expect(
        tester.widget<StarRatingInput>(find.byType(StarRatingInput)).value,
        5,
      );
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      expect(tester.widget<TextField>(comment).controller!.text, 'Uma pausa.');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Descartar avaliação?'), findsOneWidget);
      await wizardTap(tester, find.text('Continuar a avaliar'));
      expect(tester.widget<TextField>(comment).controller!.text, 'Uma pausa.');
      await wizardTap(tester, find.byType(BackButton));
      await wizardTap(tester, find.text('Descartar'));
      expect(state.visits.length, visits);
      expect(find.byType(ReviewFormPage), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('integer review saves exact criteria and one atomic visit', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    final count = state.visits.length;
    await mountWizard(tester, state);
    await wizardTap(tester, find.byKey(const ValueKey('global-star-1')));
    await wizardTap(tester, find.text('Continuar'));
    await answerDetails(tester);
    await wizardTap(tester, find.text('Continuar'));
    await wizardTap(tester, find.text('Guardar avaliação'));
    final review = state.reviews.last;
    expect(review.rating, 1);
    expect(
      [
        review.hygiene,
        review.comfort,
        review.aesthetics,
        review.paperAvailability,
      ],
      [0, 1, 3, 2],
    );
    expect(state.visits.length, count + 1);
    expect(state.visits.last.id, review.visitId);
    expect(find.byType(ReviewFormPage), findsNothing);
  });

  for (final historical in [0.0, 2.37, 4.7]) {
    testWidgets(
      'unrelated edits preserve historical score $historical exactly',
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
          rating: historical,
          paperAvailability: old.paperAvailability,
          hygiene: old.hygiene,
          comfort: old.comfort,
          aesthetics: old.aesthetics,
          tags: old.tags,
        );
        state.saveReview(legacy);
        await mountWizard(
          tester,
          state,
          page: ReviewFormPage(bathroomId: old.bathroomId, review: legacy),
        );
        expect(
          tester.widget<StarRatingInput>(find.byType(StarRatingInput)).value,
          historical,
        );
        await wizardTap(tester, find.text('Continuar'));
        await wizardTap(tester, find.text('Continuar'));
        await tester.enterText(
          find.widgetWithText(TextField, 'Comentário (opcional)'),
          'Comentário editado',
        );
        await wizardTap(tester, find.text('Guardar avaliação'));
        expect(state.reviews.first.rating, historical);
        expect(state.reviews.first.comment, 'Comentário editado');
      },
    );
  }

  testWidgets(
    'keyboard-aware tag dialog validates unrestricted emoji, duplicate labels and cancellation',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      final old = state.reviews.first;
      await mountWizard(
        tester,
        state,
        page: ReviewFormPage(bathroomId: old.bathroomId, review: old),
      );
      await wizardTap(tester, find.text('Continuar'));
      await wizardTap(tester, find.text('Continuar'));
      final comment = find.widgetWithText(TextField, 'Comentário (opcional)');
      await tester.enterText(comment, 'Rascunho intacto');
      await wizardTap(tester, find.text('+ Criar etiqueta'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      expect(find.text('Escolhe um único emoji.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Emoji'),
        '👩🏽‍💻',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome da etiqueta'),
        'Tecnologia',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.text('Adicionar etiqueta')).dy,
        lessThan(tester.view.physicalSize.height - 300),
      );
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Tecnologia'), findsOneWidget);
      await wizardTap(tester, find.text('+ Criar etiqueta'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Emoji'),
        '🇵🇹',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome da etiqueta'),
        'tecnologia',
      );
      await wizardTap(tester, find.text('Adicionar etiqueta'));
      expect(find.text('Esta etiqueta já está selecionada.'), findsOneWidget);
      await wizardTap(tester, find.text('Cancelar'));
      expect(
        tester.widget<TextField>(comment).controller!.text,
        'Rascunho intacto',
      );
      await wizardTap(tester, find.text('Guardar avaliação'));
      expect(state.reviews.first.tags.last.emoji, '👩🏽‍💻');
      expect(state.reviews.first.rating, old.rating);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'direct selectors responsive $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, width == 320 ? 740 : 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = AppState();
            addTearDown(state.dispose);
            await mountWizard(tester, state, dark: dark, scale: scale);
            await capture(tester, 'a4-global-$width-$dark-$scale');
            await wizardTap(
              tester,
              find.byKey(const ValueKey('global-star-4')),
            );
            await wizardTap(tester, find.text('Continuar'));
            expect(find.byType(Slider), findsNothing);
            if (width == 390 && scale == 1) {
              final scroll = tester.state<ScrollableState>(
                find.byType(Scrollable).first,
              );
              expect(scroll.position.maxScrollExtent, 0);
            }
            await capture(tester, 'a4-details-$width-$dark-$scale');
            await answerDetails(tester);
            await wizardTap(tester, find.text('Continuar'));
            expect(
              find.widgetWithText(TextField, 'Comentário (opcional)'),
              findsOneWidget,
            );
            await capture(tester, 'a4-tags-$width-$dark-$scale');
            await wizardTap(tester, find.text('+ Criar etiqueta'));
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Nome da etiqueta'),
              'Uma etiqueta',
            );
            await tester.ensureVisible(find.text('Adicionar etiqueta'));
            await tester.pumpAndSettle();
            await capture(tester, 'a4-tag-dialog-$width-$dark-$scale');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
