import 'widgets/alpha_feedback.dart';
import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/pages/home.dart';
import 'pages/private_synchronization.dart';
import 'auth/production_auth.dart';

class MainApp extends StatefulWidget {
  // final ColorScheme lightColorScheme;
  // final ColorScheme darkColorScheme;

  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  final feedbackObserver = FeedbackNavigatorObserver();
  @override
  void dispose() {
    feedbackObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [feedbackObserver],
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: appState.darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => appState.storageError == null
          ? AlphaFeedbackHost(
              navigatorKey: navigatorKey,
              observer: feedbackObserver,
              child: child!,
            )
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Não foi possível guardar. As alterações continuam em memória. Liberta espaço e tenta novamente antes de fechar a aplicação.',
                      ),
                      FilledButton(
                        onPressed: appState.retryStorage,
                        child: const Text('Tentar guardar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      home: appState.synchronization == null
          ? const HomePage()
          : ListenableBuilder(
              listenable: appState.synchronization!,
              builder: (context, _) => appState.synchronization!.enabled
                  ? const HomePage()
                  : AccountStorageAcceptance(
                      sync: appState.synchronization!,
                      logout: () => context.read<ProductionAuth>().logout(),
                    ),
            ),
    );
  }
}
