import 'package:bath_royale/app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bath_royale/state/app_state.dart';

void main() {
  runApp(
    // TODO: Maybe switch from context.watch<AppState> to Consumers
    ChangeNotifierProvider(create: (context) => AppState(), child: MainApp()),
  );
}

final lightColorScheme = ColorScheme.fromSeed(
  seedColor: Colors.brown,
  brightness: Brightness.light,
);
final darkColorScheme = ColorScheme.fromSeed(
  seedColor: Colors.brown,
  brightness: Brightness.dark,
);
