import 'dart:ui' show SemanticsAction;
import 'dart:convert';
import 'dart:io';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/pages/review_form.dart';
import 'package:bath_royale/pages/home.dart';
import 'package:bath_royale/pages/bathroom_form.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:bath_royale/sync/community_catalogue.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/sync/sync_coordinator.dart';
import 'package:bath_royale/sync/sync_store.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:bath_royale/widgets/alpha_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'review_wizard_test.dart' show wizardTap, answerDetails;
import 'collection_profile_test.dart' show capture;

void main() {
  setUpAll(() async {
    const fontPath = String.fromEnvironment('SESSION3_FONT');
    const emojiPath = String.fromEnvironment('SESSION3_EMOJI');
    if (fontPath.isEmpty) return;
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    for (final item in [
      ('Roboto', fontPath),
      ('Noto Color Emoji', emojiPath),
    ]) {
      if (item.$2.isEmpty) continue;
      final bytes = await File(item.$2).readAsBytes();
      await (FontLoader(
        item.$1,
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
  });

  late AppState state;
  late CommunityCatalogue catalogue;
  setUp(() {
    final cache = LocalStore(
      sqlite3.openInMemory(),
      namespace: DataNamespace.publicCatalogue('feedback-test'),
    );
    catalogue = CommunityCatalogue(
      SyncCoordinator(
        store: SyncStore(cache),
        auth: FakeAuthSession(),
        remote: FakeRemoteDataSource(),
        now: () => 1000,
      ),
    );
    state = AppState(
      bathrooms: [
        const Bathroom(id: '5', name: 'Trono de teste', createdBy: 'local'),
      ],
    )..attachCommunity(catalogue, anonymous: true);
    FeedbackLocation.home = 'explore';
  });
  tearDown(() {
    state.dispose();
    catalogue.dispose();
  });
  Future<void> mount(
    WidgetTester tester,
    FeedbackSender sender, {
    bool enabled = true,
    bool dark = false,
    double scale = 1,
    Widget? home,
  }) async {
    final key = GlobalKey<NavigatorState>();
    final observer = FeedbackNavigatorObserver();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: RepaintBoundary(
          child: MaterialApp(
            navigatorKey: key,
            navigatorObservers: [observer],
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: AlphaFeedbackHost(
                navigatorKey: key,
                observer: observer,
                enabled: enabled,
                send: sender,
                metadata: () async => {
                  'app_version': '0.1.0-test',
                  'platform_version': 'Android 16',
                },
                child: child!,
              ),
            ),
            home:
                home ??
                Builder(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Explorar')),
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(name: 'review'),
                          builder: (_) => const ReviewFormPage(bathroomId: '5'),
                        ),
                      ),
                      child: const Text('Abrir avaliação'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'anonymous feedback preserves navigation/draft and retries one durable exact submission',
    (tester) async {
      final requests = <Map<String, Object?>>[];
      Future<void> send(Map<String, Object?> payload) async {
        requests.add(Map.of(payload));
        if (requests.length == 1) throw const SocketException('offline');
      }

      await mount(tester, send);
      await wizardTap(tester, find.text('Abrir avaliação'));
      await wizardTap(tester, find.byKey(const ValueKey('global-star-4')));
      await wizardTap(tester, find.text('Continuar'));
      await answerDetails(tester);
      await wizardTap(tester, find.text('Continuar'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Comentário (opcional)'),
        'Comentário privado por guardar',
      );
      await wizardTap(
        tester,
        find.byKey(const ValueKey('alpha-feedback-button')),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'O que aconteceu?'),
        'A confirmação estava pouco visível.',
      );
      await wizardTap(tester, find.text('Enviar'));
      expect(find.textContaining('Não foi possível enviar'), findsOneWidget);
      final stored =
          catalogue.local.database
                  .select('SELECT feedback_draft FROM settings')
                  .single['feedback_draft']
              as String;
      expect(jsonDecode(stored)['attempted'], requests.single);
      expect(requests.single['screen_id'], 'review_tags');
      expect(requests.single.keys.toSet(), {
        'report_id',
        'retry_key',
        'category',
        'description',
        'app_version',
        'platform_version',
        'screen_id',
      });
      expect(
        jsonEncode(requests.single),
        isNot(contains('Comentário privado')),
      );
      await wizardTap(tester, find.text('Cancelar'));
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Comentário (opcional)'),
            )
            .controller!
            .text,
        'Comentário privado por guardar',
      );
      await wizardTap(
        tester,
        find.byKey(const ValueKey('alpha-feedback-button')),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'O que aconteceu?'),
            )
            .enabled,
        false,
      );
      await wizardTap(tester, find.text('Tentar novamente'));
      expect(requests[0], requests[1]);
      expect(find.text('O teu feedback foi enviado à equipa.'), findsOneWidget);
      await wizardTap(tester, find.text('Fechar'));
      expect(
        catalogue.local.database
            .select('SELECT feedback_draft FROM settings')
            .single['feedback_draft'],
        isNull,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Comentário (opcional)'),
            )
            .controller!
            .text,
        'Comentário privado por guardar',
      );
    },
  );
  testWidgets('feedback draft and retry secret restore after host restart', (
    tester,
  ) async {
    Map<String, Object?>? first, second;
    await mount(tester, (p) async {
      first = Map.of(p);
      throw const SocketException('lost acknowledgement');
    });
    await wizardTap(
      tester,
      find.byKey(const ValueKey('alpha-feedback-button')),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'O que aconteceu?'),
      'Uma sugestão guardada.',
    );
    await wizardTap(tester, find.text('Enviar'));
    await wizardTap(tester, find.text('Cancelar'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, (p) async {
      second = Map.of(p);
    });
    await wizardTap(
      tester,
      find.byKey(const ValueKey('alpha-feedback-button')),
    );
    await wizardTap(tester, find.text('Tentar novamente'));
    expect(second, first);
  });
  testWidgets(
    'feedback accessibility label belongs to its compact target, not the screen',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, (_) async {});
      final node = tester.getSemantics(
        find.bySemanticsLabel('Enviar feedback'),
      );
      expect(node.rect.width, lessThanOrEqualTo(48));
      expect(node.rect.height, lessThanOrEqualTo(48));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      semantics.dispose();
    },
  );
  testWidgets(
    'feedback floats above navigation without adding a bottom strip',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, (_) async {}, home: const HomePage());
      final navigation = find.byType(NavigationBar);
      final feedback = find.byKey(const ValueKey('alpha-feedback-button'));
      expect(tester.getBottomRight(navigation).dy, 844);
      expect(
        tester.getBottomRight(feedback).dy,
        lessThan(tester.getTopLeft(navigation).dy),
      );
      expect(tester.getTopLeft(feedback).dx, greaterThan(300));
    },
  );
  testWidgets(
    'creation keeps feedback separate from reachable primary actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      FeedbackLocation.home = 'bathroom_form';
      await mount(
        tester,
        (_) async {},
        home: const BathroomFormPage(),
        scale: 1.5,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final button = tester.getRect(
        find.byKey(const ValueKey('alpha-feedback-button')),
      );
      final create = tester.getRect(
        find.widgetWithText(FilledButton, 'Criar casa de banho'),
      );
      expect(button.overlaps(create), false);
      expect(create.bottom, lessThanOrEqualTo(440));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('feature can be disabled independently', (tester) async {
    await mount(tester, (_) async {}, enabled: false);
    expect(find.byKey(const ValueKey('alpha-feedback-button')), findsNothing);
  });
  testWidgets(
    'screen identifiers never use arbitrary route names or arguments',
    (tester) async {
      final observer = FeedbackNavigatorObserver();
      observer.didPush(
        MaterialPageRoute<void>(
          settings: const RouteSettings(
            name: '/history/private-user-id',
            arguments: {'email': 'private@example.invalid'},
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      expect(observer.screen, 'other');
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'feedback targets and keyboard $width dark=$dark scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(width, width == 320 ? 740 : 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewInsets);
            await mount(tester, (_) async {}, dark: dark, scale: scale);
            final feedback = find.byKey(
              const ValueKey('alpha-feedback-button'),
            );
            expect(
              tester.getSize(feedback).shortestSide,
              greaterThanOrEqualTo(48),
            );
            await wizardTap(tester, find.text('Abrir avaliação'));
            await wizardTap(
              tester,
              find.byKey(const ValueKey('global-star-3')),
            );
            await capture(tester, 'feedback-button-$width-$dark-$scale');
            await wizardTap(tester, find.text('Continuar'));
            await answerDetails(tester);
            expect(
              tester
                  .getRect(feedback)
                  .overlaps(
                    tester.getRect(
                      find.widgetWithText(FilledButton, 'Continuar'),
                    ),
                  ),
              false,
            );
            await wizardTap(tester, find.text('Continuar'));
            expect(
              tester
                  .getRect(feedback)
                  .overlaps(
                    tester.getRect(
                      find.widgetWithText(FilledButton, 'Guardar avaliação'),
                    ),
                  ),
              false,
            );
            await wizardTap(tester, feedback);
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextFormField, 'O que aconteceu?'),
              'Uma ideia para a alfa.',
            );
            await tester.ensureVisible(find.text('Enviar'));
            await tester.pumpAndSettle();
            expect(
              tester.getBottomRight(find.text('Enviar')).dy,
              lessThan(tester.view.physicalSize.height - 300),
            );
            await capture(tester, 'feedback-form-$width-$dark-$scale');
            await wizardTap(tester, find.text('Enviar'));
            expect(find.text('Obrigado!'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
