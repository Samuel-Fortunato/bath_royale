import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/pages/explore.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:bath_royale/widgets/wc_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'compact cards distinguish community and latest personal ratings',
    (tester) async {
      final date = DateTime.utc(2026);
      Review makeReview(String id, String author, double rating) => Review(
        id: id,
        visitId: 'visit-$id',
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
        visits: [
          Visit(
            id: 'visit-other',
            bathroomId: 'wc',
            userId: 'other',
            visitedAt: date,
          ),
        ],
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
      expect(find.textContaining('A tua avaliação:'), findsNothing);
      expect(find.textContaining('★ 5,0 / 5'), findsOneWidget);
      expect(find.text('Por descobrir'), findsOneWidget);
      state.saveReview(
        makeReview('mine', 'me', 1),
        newVisit: Visit(
          id: 'visit-mine',
          bathroomId: 'wc',
          userId: 'me',
          visitedAt: date,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A tua avaliação: 1,0 / 5'), findsOneWidget);
      expect(find.textContaining('★ 3,0 / 5'), findsOneWidget);
      expect(find.textContaining('Poltrona'), findsNothing);
      expect(find.text('✓ Descoberta'), findsOneWidget);
      state.saveReview(makeReview('mine', 'me', 4));
      await tester.pumpAndSettle();
      expect(find.text('A tua avaliação: 4,0 / 5'), findsOneWidget);
      expect(find.text('A tua avaliação: 1,0 / 5'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
    expect(find.text('Comunidade: sem avaliações'), findsOneWidget);
    expect(find.textContaining('A tua avaliação:'), findsNothing);
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
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('★ 4 ou mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem avaliações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Os meus tronos'));
      await tester.tap(find.text('Os meus tronos'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('♥ Favoritos'));
      await tester.tap(find.text('♥ Favoritos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(find.text('Nome de Teste'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
}
