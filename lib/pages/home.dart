import 'package:bath_royale/pages/explore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bath_royale/state/app_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    AppState appState = context.watch<AppState>();

    return Scaffold(
      // TODO: appbar changing color when scrolling
      appBar: AppBar(
        title: Text('Bath Royale', style: TextTheme.of(context).headlineMedium),
        actions: [
          IconButton(
            onPressed: () {
              appState.toggleTheme();
            },
            icon: Icon(appState.darkMode ? Icons.dark_mode : Icons.light_mode),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (value) {
          setState(() {
            tabIndex = value;
          });
        },
        destinations: [
          NavigationDestination(label: "Explorar", icon: Icon(Icons.wc)),
          NavigationDestination(
            label: "Rankings",
            icon: Icon(Icons.leaderboard),
          ),
          NavigationDestination(label: "Perfil", icon: Icon(Icons.person)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: Icon(Icons.addchart),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: IndexedStack(
        index: tabIndex,
        children: [ExplorePage(), Placeholder(), Placeholder()],
      ),
    );
  }
}
