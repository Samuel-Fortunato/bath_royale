import 'collection_profile_test.dart' show capture;
import 'package:flutter/services.dart';
import '../tool/local_development.dart' show developmentAccounts;
import 'package:bath_royale/pages/private_synchronization.dart';
import 'package:bath_royale/storage/bathroom_repository.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/sync/private_sync_controller.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/pages/authentication.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/theme/theme.dart';
import 'production_auth_test.dart'
    show
        MemoryGuard,
        MemoryVault,
        DelayedLoginClient,
        PasswordClient,
        fixtureSession;
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
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/visit.dart';
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
  setUpAll(() async {
    const font = String.fromEnvironment('SESSION3_FONT');
    if (font.isEmpty) return;
    final bytes = await File(font).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  });
  testWidgets(
    'password change requires current proof with reachable keyboard actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 390.0]) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 1.5]) {
            tester.view.physicalSize = Size(width, 780);
            final vault = MemoryVault();
            final client = PasswordClient();
            final auth = ProductionAuth(
              AuthConfiguration('https://password.test', 'client'),
              vault,
              restorationGuard: vault.guard,
              client: client,
              now: () => -1,
            );
            client.response.complete(AuthResponse(session: fixtureSession()));
            await auth.login('fiction@example.invalid', 'old-secret');
            await tester.pumpWidget(
              ChangeNotifierProvider.value(
                value: auth,
                child: RepaintBoundary(
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        viewInsets: const EdgeInsets.only(bottom: 240),
                      ),
                      child: child!,
                    ),
                    home: const AuthenticationPage(
                      initialFlow: AuthFlow.password,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final submit = find.widgetWithText(
              FilledButton,
              'Guardar palavra-passe',
            );
            await tester.ensureVisible(submit);
            await tester.pumpAndSettle();
            await tester.tap(submit);
            await tester.pumpAndSettle();
            expect(
              find.text('Introduz a palavra-passe atual.'),
              findsOneWidget,
            );
            expect(client.update, isNull);
            final current = find.widgetWithText(
              TextField,
              'Palavra-passe atual',
            );
            final password = find.widgetWithText(
              TextField,
              'Nova palavra-passe',
            );
            await tester.ensureVisible(current);
            await tester.pumpAndSettle();
            await tester.enterText(current, 'old-secret');
            expect(tester.widget<TextField>(current).obscureText, isTrue);
            await tester.ensureVisible(password);
            await tester.pumpAndSettle();
            await tester.enterText(password, 'new-secret');
            await tester.ensureVisible(submit);
            await tester.pumpAndSettle();
            await capture(tester, 'a51-password-$width-$dark-$scale');
            await tester.tap(submit);
            await tester.pumpAndSettle();
            expect(client.update!.toJson()['current_password'], 'old-secret');
            expect(find.text('Palavra-passe atualizada.'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            auth.dispose();
          }
        }
      }
    },
  );
  testWidgets(
    'development account selector is one tap and ordinary entry has no shortcut',
    (tester) async {
      final vault = MemoryVault();
      final client = DelayedLoginClient()
        ..response.complete(AuthResponse(session: fixtureSession()));
      final auth = ProductionAuth(
        AuthConfiguration.localDevelopment(
          'https://localhost:55504',
          'local-development-client',
        ),
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: WelcomePage()),
        ),
      );
      expect(find.textContaining('Contas de teste'), findsNothing);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: Provider<AccountEntryExtras>.value(
            value: AccountEntryExtras(
              (_) => developmentAccounts([
                {
                  'email': 'unit@example.invalid',
                  'password': 'test-only-input',
                },
              ]),
            ),
            child: const MaterialApp(home: WelcomePage()),
          ),
        ),
      );
      expect(find.text('unit@example.invalid'), findsOneWidget);
      await tester.tap(find.text('unit@example.invalid'));
      await tester.pumpAndSettle();
      expect(auth.current, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
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
        expect(n.kind, isNot('guest'), reason: 'Guest files remain archived');
        if (n.isAccount) opens++;
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
      expect(find.byType(HomePage), findsOneWidget);
      expect(
        find.widgetWithText(NavigationDestination, 'Conta'),
        findsOneWidget,
      );
      expect(
        tester.element(find.byType(HomePage)).read<AppState>().readOnly,
        true,
      );
      await auth.login('first@example.invalid', 'password');
      await tester.pumpAndSettle();
      expect(find.byType(AccountStorageAcceptance), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aceitar e continuar'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceitar e continuar'));
      await tester.pumpAndSettle();
      var state = tester.element(find.byType(HomePage)).read<AppState>();
      expect(state.allBathrooms, isEmpty);
      // Retained A2 private records are inserted through the private repository path.
      final bathroom = Bathroom(
        id: AppState.newEntityId(),
        name: 'Trono da conta A',
        createdBy: state.currentUserId,
      );
      state.repository!.createBathroom(bathroom);
      state.reloadAccountData();
      final visit = Visit(
        id: AppState.newEntityId(),
        bathroomId: bathroom.id,
        userId: state.currentUserId,
        visitedAt: DateTime.utc(2026, 11, 26),
      );
      state.repository!.recordVisit(visit);
      state.repository!.setFavourite(state.currentUserId, bathroom.id, true);
      state.repository!.saveReview(
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
        isNew: true,
      );
      state.reloadAccountData();
      await tester.pumpAndSettle();
      // Profile presents navigation to the dedicated flow, with no embedded form.
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthenticationPanel), findsNothing);
      await tester.tap(find.byTooltip('Definições'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conta e segurança'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthenticationPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await auth.logout();
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(HomePage)).read<AppState>().readOnly,
        true,
      );
      await tester.tap(find.text('Conta'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      await auth.login('second@example.invalid', 'password');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Aceitar e continuar'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceitar e continuar'));
      await tester.pumpAndSettle();
      state = tester.element(find.byType(HomePage)).read<AppState>();
      expect(state.allBathrooms, isEmpty);
      expect(state.visits, isEmpty);
      expect(state.reviews, isEmpty);
      state.toggleTheme();
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
      expect(state.legacyBathrooms.single.id, bathroom.id);
      expect(state.visits.single.id, visit.id);
      expect(state.reviews.single.rating, 4.5);
      expect(state.activityFor(bathroom.id).isFavorite, isTrue);
      expect(state.repository!.syncContext, isNotNull);
      expect(state.synchronization!.enabled, isTrue);
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
      expect(find.textContaining('Recuperação e eliminação:'), findsOneWidget);
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
      expect(opened, ['', first.user.id, second.user.id]);
      expect(find.byType(AccountStorageAcceptance), findsOneWidget);
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
      await tester.ensureVisible(find.text('Voltar a entrar'));
      await tester.pumpAndSettle();
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
      expect(find.text('Terminar sessão'), findsNothing);
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
      expect(find.byType(AccountStorageAcceptance), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Explorar'), findsOneWidget);
      await tester.tap(find.text('Conta'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
      expect(
        find.widgetWithText(NavigationDestination, 'Conta'),
        findsOneWidget,
      );
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
      await tester.ensureVisible(find.text('Voltar a entrar'));
      await tester.pumpAndSettle();
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
            : find.widgetWithText(TextFormField, 'Nome da casa de banho');
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
  testWidgets(
    'account storage explains acceptance, gates transfers and removes optional modes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final namespace = DataNamespace.account('test', 'private');
      final local = LocalStore(sqlite3.openInMemory(), namespace: namespace);
      final state = AppState.restoreAccountForTesting(
        BathroomRepository(
          local,
          syncContext: SyncWriteContext.account(namespace),
        ),
      );
      final auth = FakeAuthSession()
        ..change(SessionIdentity(namespace, 100000));
      final remote = FakeRemoteDataSource();
      final sync = PrivateSyncController(
        state: state,
        coordinator: SyncCoordinator(
          store: SyncStore(local),
          auth: auth,
          remote: remote,
          now: () => 1000,
          authorized: () => SyncStore(local).hasConsent,
        ),
        renew: () async {},
      );
      state.synchronization = sync;
      addTearDown(() {
        state.dispose();
        local.close();
      });
      state.createBathroom('Sem consentimento, sem envio');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: PrivateSynchronizationPage(sync: sync),
        ),
      );
      expect(remote.requests, isEmpty);
      expect(sync.enabled, false);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountStorageAcceptance(sync: sync, logout: () {}),
        ),
      );
      expect(
        find.textContaining('O histórico privado anterior não é publicado'),
        findsOneWidget,
      );
      expect(find.text('Política de privacidade'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aceitar e continuar'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceitar e continuar'));
      await tester.pumpAndSettle();
      expect(sync.enabled, true);
      expect(remote.requests.length, 1);
      await tester.pumpWidget(
        MaterialApp(home: PrivateSynchronizationPage(sync: sync)),
      );
      expect(find.textContaining('Pausar'), findsNothing);
      expect(find.textContaining('Ativar'), findsNothing);
      expect(find.text('Sincronização privada em dia'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
