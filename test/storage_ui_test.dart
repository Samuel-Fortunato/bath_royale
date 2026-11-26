import 'dart:async';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/pages/profile.dart';
import 'production_auth_test.dart' show MemoryVault;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:provider/provider.dart';
import 'package:bath_royale/state/account_state_scope.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/widgets/account_state_provider.dart';
import 'package:bath_royale/pages/bathroom_form.dart';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/main.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/storage/local_store.dart';

void main() {
  testWidgets(
    'optional auth controls validate input, hide passwords and block unsafe transitions',
    (tester) async {
      final auth = ProductionAuth(
        AuthConfiguration('https://example.test', 'client'),
        MemoryVault(),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AuthenticationPanel()),
            ),
          ),
        ),
      );
      expect(find.textContaining('sem criar uma conta'), findsOneWidget);
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(
        find.text('Introduz um endereço de email válido.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'test@example.invalid',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Palavra-passe'),
        'short',
      );
      await tester.tap(find.text('Criar conta'));
      await tester.pump();
      expect(find.text('Usa pelo menos 8 caracteres.'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar palavra-passe'));
      await tester.pump();
      expect(find.byTooltip('Ocultar palavra-passe'), findsOneWidget);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AuthenticationPanel(canTransition: false),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(find.textContaining('Termina ou cancela'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
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
  for (final reviewEditor in [false, true]) {
    testWidgets(
      '${reviewEditor ? 'review' : 'bathroom'} draft survives session loss and blocks replacement',
      (tester) async {
        var now = 1000;
        final a = DataNamespace.account('offline-test', 'subject-A');
        final b = DataNamespace.account('offline-test', 'subject-B');
        final auth = _ObservedAuth(now: () => now)
          ..change(SessionIdentity(a, now + 60000));
        final scope = AccountStateScope.forTesting(
          auth: auth,
          openStore: (namespace) async =>
              LocalStore(sqlite3.openInMemory(), namespace: namespace),
          now: () => now,
        );
        await scope.select(a);
        final state = scope.state!;
        final bathroom = state.createBathroom('Trono A');
        if (reviewEditor) {
          final visit = state.recordVisit(
            bathroom.id,
            visitedAt: DateTime.utc(2026),
          );
          state.saveReview(
            Review(
              id: 'review-A',
              visitId: visit.id,
              bathroomId: bathroom.id,
              authorId: a.subject,
              createdAt: visit.visitedAt,
              rating: 4,
              paperAvailability: 2,
              hygiene: 3,
              comfort: 2,
              aesthetics: 1,
            ),
          );
        }
        await tester.pumpWidget(
          AccountStateProvider.forTesting(
            scope: scope,
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  final selected = context.watch<AppState>();
                  if (selected.currentUserId != a.subject) {
                    return const Text('Conta B vazia');
                  }
                  return reviewEditor
                      ? ReviewFormPage(
                          bathroomId: bathroom.id,
                          review: state.reviews.single,
                        )
                      : const BathroomFormPage();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(state.hasUncommittedWork, isTrue);
        if (reviewEditor) {
          await tester.ensureVisible(find.text('Continuar'));
          await tester.tap(find.text('Continuar'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Continuar'));
          await tester.tap(find.text('Continuar'));
          await tester.pumpAndSettle();
        }
        final field = reviewEditor
            ? find.widgetWithText(TextField, 'Comentário (opcional)')
            : find.byType(TextFormField);
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Rascunho só de A');
        now += 60000;
        auth.checkExpiry();
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        expect(state.hasUncommittedWork, isTrue);
        auth.change(SessionIdentity(b, now + 60000));
        await expectLater(scope.select(b), throwsStateError);
        await tester.pumpAndSettle();
        expect(find.text('Conta B vazia'), findsNothing);
        auth.change(SessionIdentity(a, now + 60000));
        await tester.pumpAndSettle();
        final text = reviewEditor
            ? tester.widget<TextField>(field).controller!.text
            : tester.widget<TextFormField>(field).controller!.text;
        expect(text, 'Rascunho só de A');
        // Explicitly closing the editor releases its retention guard.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(state.hasUncommittedWork, isFalse);
        scope.dispose();
        expect(auth.listenerCount, 0);
        auth.dispose();
      },
    );
  }

  testWidgets('Provider replacement resets routes and removes old listeners', (
    tester,
  ) async {
    final a = DataNamespace.account('offline-test', 'subject-A');
    final b = DataNamespace.account('offline-test', 'subject-B');
    final auth = _ObservedAuth(now: () => 1000)
      ..change(SessionIdentity(a, 60000));
    final scope = AccountStateScope.forTesting(
      auth: auth,
      openStore: (namespace) async =>
          LocalStore(sqlite3.openInMemory(), namespace: namespace),
      now: () => 1000,
    );
    await scope.select(a);
    await tester.pumpWidget(
      AccountStateProvider.forTesting(
        scope: scope,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final state = context.watch<AppState>();
              return TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Text('Rota privada A'),
                  ),
                ),
                child: Text(state.currentUserId),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(a.subject));
    await tester.pumpAndSettle();
    expect(find.text('Rota privada A'), findsOneWidget);
    auth.change(SessionIdentity(b, 60000));
    await scope.select(b);
    await tester.pumpAndSettle();
    expect(find.text('Rota privada A'), findsNothing);
    expect(find.text(b.subject), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    scope.dispose();
    expect(auth.listenerCount, 0);
    auth.change(SessionIdentity(a, 60000));
    auth.dispose();
  });
}

class _ObservedAuth extends FakeAuthSession {
  _ObservedAuth({required super.now});
  int listenerCount = 0;
  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }
}
