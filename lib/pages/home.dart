import 'bathroom_form.dart';
import 'collection.dart';
import 'rankings.dart';
import 'profile.dart';
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
      appBar: AppBar(
        title: Text(
          const ['Explorar', 'Coleção', 'Rankings', 'Perfil'][tabIndex],
        ),
        actions: [
          if (tabIndex == 3)
            IconButton(
              tooltip: 'Definições',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: appState,
                    child: const SettingsPage(),
                  ),
                ),
              ),
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
            label: "Coleção",
            icon: Icon(Icons.collections_bookmark_outlined),
          ),
          NavigationDestination(
            label: "Rankings",
            icon: Icon(Icons.leaderboard),
          ),
          NavigationDestination(label: "Perfil", icon: Icon(Icons.person)),
        ],
      ),
      floatingActionButton: tabIndex != 0
          ? null
          : FloatingActionButton(
              tooltip: 'Criar casa de banho',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: appState,
                    child: const BathroomFormPage(),
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: tabIndex,
          children: [
            ExplorePage(),
            CollectionPage(),
            RankingsPage(),
            ProfilePage(),
          ],
        ),
      ),
    );
  }
}
