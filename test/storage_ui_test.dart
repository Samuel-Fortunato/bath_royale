import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bath_royale/main.dart';
import 'package:bath_royale/storage/local_store.dart';

void main() {
  testWidgets(
    'startup displays loading, preserves failures and retries with isolated storage',
    (tester) async {
      final pending = Completer<LocalStore>();
      var attempts = 0;
      await tester.pumpWidget(
        StorageBootstrap(
          openStore: () {
            attempts++;
            if (attempts == 1) return pending.future;
            return Future.value(LocalStore(sqlite3.openInMemory()));
          },
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ficheiros foram preservados'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Explorar'), findsOneWidget);
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
