import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_filters.dart';
import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:bath_royale/widgets/wc_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('evaluation updates all fields and copies tags', () {
    final bathroom = Bathroom(id: '1', name: 'Test');
    final tags = ['clean'];
    bathroom.evaluate(
      rating: 4.5,
      paperAvailability: 2,
      hygiene: 3,
      confort: 4,
      aesthetics: 1,
      tags: tags,
    );
    tags.add('changed');
    expect(bathroom.reviewed, isTrue);
    expect(bathroom.rating, 4.5);
    expect(bathroom.paperAvailability, 2);
    expect(bathroom.hygiene, 3);
    expect(bathroom.confort, 4);
    expect(bathroom.aesthetics, 1);
    expect(bathroom.tags, ['clean']);
    expect(bathroom.lastReviewed, isNotNull);
    bathroom.toggleFavorite();
    expect(bathroom.copyWith().isFavorite.value, isTrue);
  });

  test('sample state is independent and rating filters exclude unreviewed', () {
    final first = AppState();
    final second = AppState();
    first.allBathrooms.first.toggleFavorite();
    expect(second.allBathrooms.first.isFavorite.value, isFalse);
    final unreviewed = first.allBathrooms.last;
    for (final filter in bathroomFilters.where(
      (f) => [
        BathroomFilterID.goodRating,
        BathroomFilterID.badRating,
        BathroomFilterID.confy,
        BathroomFilterID.instagramable,
      ].contains(f.id),
    )) {
      expect(filter.test(unreviewed), isFalse);
    }
    first.dispose();
    second.dispose();
  });

  testWidgets('unreviewed card does not show invented ratings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: WcCard(
            bathroom: Bathroom(id: '1', name: 'Test'),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Ainda não avaliada'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.textContaining('Tudo cagado'), findsNothing);
  });

  testWidgets(
    'favourite filter updates immediately and incompatible filters clear',
    (tester) async {
      final state = AppState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: ExplorePage()),
          ),
        ),
      );
      await tester.tap(find.text('✨ Avaliação positiva'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🚽 Não avaliadas'));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('⭐ Favoritos'));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.star));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
}
