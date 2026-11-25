import 'package:bath_royale/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bath_royale/state/app_state.dart';
import 'package:bath_royale/pages/home.dart';

class MainApp extends StatelessWidget {
  // final ColorScheme lightColorScheme;
  // final ColorScheme darkColorScheme;

  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<AppState>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: appState.darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => appState.storageError == null
          ? child!
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
      home: HomePage(),
    );
  }
}
