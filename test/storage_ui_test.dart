import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/pages/authentication.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/theme/theme.dart';
import 'production_auth_test.dart'
    show MemoryGuard, MemoryVault, DelayedLoginClient, fixtureSession;
import 'package:supabase/supabase.dart'
    show AuthResponse, AuthException, Session;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Session;
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

class SequenceClient extends DelayedLoginClient {
  final List<AuthResponse> responses;
  SequenceClient(this.responses);
  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async => responses.removeAt(0);
}

void main() {
  testWidgets(
    'welcome routes have visible and system back; registration retains invalid password',
    (tester) async {
      final vault = MemoryVault();
      final auth = ProductionAuth(
        AuthConfiguration.localAlpha(
          'https://localhost:55474',
          'local-device-client',
        ),
        vault,
        restorationGuard: vault.guard,
        client: DelayedLoginClient(),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: WelcomePage()),
        ),
      );
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'friend@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Palavra-passe'),
        'short',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Criar conta'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();
      expect(find.text('Usa pelo menos 8 caracteres.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Palavra-passe'))
            .controller!
            .text,
        'short',
      );
      expect(find.widgetWithText(FilledButton, 'Criar conta'), findsOneWidget);
      expect(auth.busy, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      final emailField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Email'),
      );
      expect(emailField.keyboardType, TextInputType.emailAddress);
      expect(emailField.textInputAction, TextInputAction.next);
      expect(emailField.autofillHints, contains(AutofillHints.username));
      expect(find.byType(AutofillGroup), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  testWidgets(
    'A1 gate preserves legacy bytes and account records across logout and restart',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('bath-a1-upgrade-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final legacyFile = File('${directory.path}/legacy.sqlite3');
      final legacy = LocalStore(sqlite3.open(legacyFile.path));
      final old = AppState.restore(legacy);
      old.createBathroom('Trono anterior');
      old.toggleFavorite(old.allBathrooms.last.id);
      old.dispose();
      legacy.close();
      final original = legacyFile.readAsBytesSync();
      final vault = MemoryVault();
      final first = fixtureSession();
      final second = Session.fromJson({
        ...first.toJson(),
        'user': {
          ...first.user.toJson(),
          'id': '22222222-2222-4222-8222-222222222222',
          'email': 'second@example.invalid',
        },
      })!;
      final config = AuthConfiguration.localAlpha(
        'https://localhost:55474',
        'local-device-client',
      );
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: SequenceClient([
          AuthResponse(session: first),
          AuthResponse(session: second),
          AuthResponse(session: first),
        ]),
      );
      var opens = 0;
      Future<LocalStore> open(DataNamespace n) async {
        expect(n.isAccount, isTrue, reason: 'Guest file must never open in A1');
        opens++;
        return LocalStore(
          sqlite3.open('${directory.path}/${n.fileName}'),
          namespace: n,
        );
      }

      await tester.pumpWidget(
        AuthenticatedBootstrap(createAuth: () => auth, openStore: open),
      );
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      await auth.login('first@example.invalid', 'password');
      await tester.pumpAndSettle();
      var state = tester.element(find.byType(HomePage)).read<AppState>();
      expect(state.allBathrooms, isEmpty);
      final bathroom = state.createBathroom('Trono da conta A');
      final visit = state.recordVisit(
        bathroom.id,
        visitedAt: DateTime.utc(2026, 11, 26),
      );
      state.toggleFavorite(bathroom.id);
      state.saveReview(
        Review(
          id: 'a1-review',
          visitId: visit.id,
          bathroomId: bathroom.id,
          authorId: state.currentUserId,
          createdAt: visit.visitedAt,
          rating: 4.5,
          paperAvailability: 2,
          hygiene: 4,
          comfort: 3,
          aesthetics: 2,
        ),
      );
      await tester.pumpAndSettle();
      // Profile presents navigation to the dedicated flow, with no embedded form.
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthenticationPanel), findsNothing);
      await tester.tap(find.text('A minha conta'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthenticationPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      await auth.login('second@example.invalid', 'password');
      await tester.pumpAndSettle();
      state = tester.element(find.byType(HomePage)).read<AppState>();
      expect(state.allBathrooms, isEmpty);
      expect(state.visits, isEmpty);
      expect(state.reviews, isEmpty);
      state.createBathroom('Trono da conta B');
      await auth.logout();
      await auth.login('first@example.invalid', 'password');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: DelayedLoginClient(),
      );
      await tester.pumpWidget(
        AuthenticatedBootstrap(createAuth: () => restored, openStore: open),
      );
      await tester.pumpAndSettle();
      state = tester.element(find.byType(HomePage)).read<AppState>();
      expect(state.allBathrooms.single.id, bathroom.id);
      expect(state.visits.single.id, visit.id);
      expect(state.reviews.single.rating, 4.5);
      expect(state.activityFor(bathroom.id).isFavorite, isTrue);
      expect(state.repository!.syncContext, isNull);
      expect(legacyFile.readAsBytesSync(), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'local alpha shows loading and visible invalid-credential feedback',
    (tester) async {
      final client = DelayedLoginClient();
      final vault = MemoryVault();
      final auth = ProductionAuth(
        AuthConfiguration.localAlpha(
          'https://localhost:55474',
          'local-device-client',
        ),
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: AuthenticationPage()),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'friend@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Palavra-passe'),
        'x',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Entrar'))
            .onPressed,
        isNull,
      );
      client.response.completeError(
        const AuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Email ou palavra-passe incorretos.').hitTestable(),
        findsOneWidget,
      );
      expect(auth.current, isNull);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.ensureVisible(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'A recuperação da palavra-passe não está disponível',
        ),
        findsOneWidget,
      );
      expect(find.text('Enviar instruções'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Email ou palavra-passe incorretos.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'dedicated alpha auth at $width px dark=$dark with keyboard and large text',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final vault = MemoryVault();
          final auth = ProductionAuth(
            AuthConfiguration.localAlpha(
              'https://localhost:55474',
              'local-device-client',
            ),
            vault,
            restorationGuard: vault.guard,
          );
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.5),
                    viewInsets: const EdgeInsets.only(bottom: 250),
                  ),
                  child: child!,
                ),
                home: const AuthenticationPage(),
              ),
            ),
          );
          await tester.ensureVisible(find.text('Criar conta'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Criar conta'));
          await tester.pumpAndSettle();
          expect(find.textContaining('sem confirmar o email'), findsOneWidget);
          expect(find.textContaining('Já recebi'), findsNothing);
          await tester.ensureVisible(
            find.widgetWithText(FilledButton, 'Criar conta'),
          );
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(FilledButton, 'Criar conta').hitTestable(),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byTooltip('Mostrar palavra-passe'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Mostrar palavra-passe'));
          await tester.pump();
          expect(find.byTooltip('Ocultar palavra-passe'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
        },
      );
    }
  }

  testWidgets(
    'a failed stale store open follows the latest rapid account change',
    (tester) async {
      final vault = MemoryVault();
      final first = fixtureSession();
      final second = Session.fromJson({
        ...first.toJson(),
        'user': {
          ...first.user.toJson(),
          'id': '22222222-2222-4222-8222-222222222222',
          'email': 'second@example.invalid',
        },
      })!;
      final client = SequenceClient([
        AuthResponse(session: first),
        AuthResponse(session: second),
      ]);
      final auth = ProductionAuth(
        AuthConfiguration('https://example.test', 'client'),
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      final gate = Completer<LocalStore>();
      final opened = <String>[];
      await tester.pumpWidget(
        AuthenticatedBootstrap(
          createAuth: () => auth,
          openStore: (namespace) async {
            opened.add(namespace.subject);
            if (namespace.subject == first.user.id) return gate.future;
            return LocalStore(sqlite3.openInMemory(), namespace: namespace);
          },
        ),
      );
      await tester.pumpAndSettle();
      await auth.login('first@example.invalid', 'password');
      await tester.pump();
      await auth.login('second@example.invalid', 'password');
      gate.completeError(StateError('old account file failed'));
      await tester.pumpAndSettle();
      expect(opened, [first.user.id, second.user.id]);
      expect(find.widgetWithText(AppBar, 'Explorar'), findsOneWidget);
      expect(find.textContaining('ficheiros foram preservados'), findsNothing);
      expect(auth.current!.namespace.subject, second.user.id);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'authentication flows stay separate and show private email without UUID',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vault = MemoryVault();
      final config = AuthConfiguration('https://example.test', 'client');
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: DelayedLoginClient(),
      );
      Widget panel() => ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: AuthenticationPanel()),
          ),
        ),
      );
      await tester.pumpWidget(panel());
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Código ou ligação do email'), findsNothing);
      await tester.ensureVisible(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enviar instruções'), findsOneWidget);
      expect(find.text('Palavra-passe'), findsNothing);
      await tester.ensureVisible(
        find.text('Já tenho um código de recuperação'),
      );
      await tester.tap(find.text('Já tenho um código de recuperação'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Validar recuperação'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Voltar a entrar'));
      await tester.tap(find.text('Voltar a entrar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Já tenho um código de confirmação'),
      );
      await tester.tap(find.text('Já tenho um código de confirmação'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Confirmar email'),
        findsOneWidget,
      );
      expect(find.text('Validar recuperação'), findsNothing);
      vault.guard.values[config.environment] = true;
      vault.values[config.storageKey] = jsonEncode({
        ...fixtureSession().toJson(),
        'bath_password_recovery': true,
      });
      await auth.restore();
      // A real account selection remounts this panel. Recovery intent must survive.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(panel());
      expect(find.text('fiction@example.invalid'), findsOneWidget);
      expect(find.textContaining(fixtureSession().user.id), findsNothing);
      expect(find.text('Nova palavra-passe'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Guardar palavra-passe'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  testWidgets('periodic renewal is quiet while the session is valid', (
    tester,
  ) async {
    final client = DelayedLoginClient();
    final vault = MemoryVault();
    final auth = ProductionAuth(
      AuthConfiguration('https://example.test', 'client'),
      vault,
      restorationGuard: vault.guard,
      client: client,
    );
    await auth.restore();
    client.response.complete(
      AuthResponse(
        session: fixtureSession()
          ..expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      ),
    );
    await auth.login('fiction@example.invalid', 'password');
    auth.message = 'Mensagem a preservar';
    final generation = auth.generation;
    var notifications = 0;
    auth.addListener(() => notifications++);
    await tester.pump(const Duration(seconds: 45));
    expect(auth.message, 'Mensagem a preservar');
    expect(auth.generation, generation);
    expect(notifications, 0);
    auth.dispose();
  });

  testWidgets(
    'configured startup retries a failed account store and returns to authentication',
    (tester) async {
      final vault = MemoryVault();
      final config = AuthConfiguration('https://example.test', 'client');
      vault.guard.values[config.environment] = true;
      vault.values[config.storageKey] = jsonEncode(fixtureSession().toJson());
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: DelayedLoginClient(),
      );
      var fail = true;
      var accountOpens = 0;
      await tester.pumpWidget(
        AuthenticatedBootstrap(
          createAuth: () => auth,
          openStore: (namespace) async {
            if (namespace.isAccount) {
              accountOpens++;
              if (fail) throw StateError('disk unavailable');
            }
            return LocalStore(sqlite3.openInMemory(), namespace: namespace);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ficheiros foram preservados'),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(accountOpens, 2);
      expect(find.widgetWithText(AppBar, 'Explorar'), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Explorar'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      expect(find.byType(WelcomePage), findsOneWidget);
      expect(auth.current, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('authentication completion tolerates a disposed panel', (
    tester,
  ) async {
    final client = DelayedLoginClient();
    final auth = ProductionAuth(
      AuthConfiguration('https://example.test', 'client'),
      MemoryVault(),
      restorationGuard: MemoryGuard(),
      client: client,
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'fiction@example.invalid',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Palavra-passe'),
      'password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    client.response.complete(AuthResponse(session: fixtureSession()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    auth.dispose();
  });

  testWidgets(
    'optional auth controls validate input, hide passwords and block unsafe transitions',
    (tester) async {
      final auth = ProductionAuth(
        AuthConfiguration('https://example.test', 'client'),
        MemoryVault(),
        restorationGuard: MemoryGuard(),
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
      expect(
        find.textContaining('Os dados anteriores estão preservados'),
        findsOneWidget,
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Palavra-passe'),
        'short',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();
      expect(find.text('Usa pelo menos 8 caracteres.'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar palavra-passe'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ocultar palavra-passe'), findsOneWidget);
      await tester.tap(find.text('Voltar a entrar'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
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
      await tester.pumpAndSettle();
      expect(find.textContaining('Termina ou cancela'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
  testWidgets('unconfigured previews expose no writable personal identity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AuthenticationUnavailablePage()),
    );
    expect(
      find.textContaining('dados anteriores continuam guardados'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Explorar'), findsNothing);
  });
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
