import 'authentication.dart';
import 'bathroom_form.dart';
import 'collection.dart';
import 'rankings.dart';
import 'profile.dart';
import 'explore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tabIndex = 0;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tabs = state.readOnly
        ? <Widget>[
            const ExplorePage(),
            const RankingsPage(),
            const WelcomePage(),
          ]
        : <Widget>[
            const ExplorePage(),
            const CollectionPage(),
            const RankingsPage(),
            const ProfilePage(),
          ];
    final labels = state.readOnly
        ? ['Explorar', 'Rankings', 'Conta']
        : ['Explorar', 'Coleção', 'Rankings', 'Perfil'];
    final icons = state.readOnly
        ? [Icons.wc, Icons.leaderboard, Icons.login]
        : [
            Icons.wc,
            Icons.collections_bookmark_outlined,
            Icons.leaderboard,
            Icons.person,
          ];
    final index = tabIndex.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(labels[index]),
        actions: [
          if (!state.readOnly && index == 3)
            IconButton(
              tooltip: 'Definições',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: state,
                    child: const SettingsPage(),
                  ),
                ),
              ),
            ),
          if ((state.canCreateBathroom ||
                  (!state.readOnly && !state.communityEnabled)) &&
              index == 0)
            IconButton(
              tooltip: 'Criar casa de banho',
              icon: const Icon(Icons.add_business_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: state,
                    child: const BathroomFormPage(),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => tabIndex = v),
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(label: labels[i], icon: Icon(icons[i])),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: index, children: tabs),
      ),
    );
  }
}
