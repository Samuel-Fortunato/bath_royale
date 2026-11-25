import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/theme/theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('local profile and tab actions on narrow screen, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      addTearDown(state.dispose);
      state.toggleFavorite('0');
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const HomePage(),
          ),
        ),
      );
      expect(find.byTooltip('Criar casa de banho'), findsOneWidget);
      for (final tab in ['Coleção', 'Rankings', 'Perfil']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('O teu perfil'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Os meus favoritos'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Os meus favoritos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEM - 3º piso'));
      await tester.pumpAndSettle();
      expect(find.text('Comunidade'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explorar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Criar casa de banho'), findsOneWidget);
    });
  }
}
