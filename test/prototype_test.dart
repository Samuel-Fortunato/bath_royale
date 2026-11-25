import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:bath_royale/widgets/wc_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('cards show personal ratings and rebuild after review updates', (
    tester,
  ) async {
    final date = DateTime.utc(2026);
    Review makeReview(String id, String author, double rating) => Review(
      id: id,
      bathroomId: 'wc',
      authorId: author,
      createdAt: date,
      rating: rating,
      paperAvailability: 2,
      hygiene: 4,
      comfort: 4,
      aesthetics: 4,
    );
    final state = AppState(
      currentUserId: 'me',
      bathrooms: [const Bathroom(id: 'wc', name: 'Test', createdBy: 'other')],
      reviews: [makeReview('other', 'other', 5)],
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: ExplorePage()),
        ),
      ),
    );
    expect(find.text('Ainda não avaliada'), findsOneWidget);
    expect(find.text('5.0'), findsNothing);
    state.saveReview(makeReview('mine', 'me', 1));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não avaliada'), findsNothing);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('3.0'), findsNothing);
    expect(find.textContaining('Poltrona'), findsOneWidget);
    state.saveReview(makeReview('mine', 'me', 4));
    await tester.pumpAndSettle();
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('1.0'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unreviewed card does not show invented ratings', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: WcCard(
            entry: state.entries.last,
            toggleFavorite: () {},
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
