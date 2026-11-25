import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/wc_card.dart';
import 'collection.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    void open(String title, Widget page) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: page,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Center(
              child: CircleAvatar(
                radius: 32,
                child: Icon(Icons.person_outline, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'O teu perfil',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              'Perfil local',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            const LocalStatistics(includeDiscoveries: true),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('Os meus favoritos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open('Os meus favoritos', const FavouritesList()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Histórico de atividade'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open('Histórico de atividade', const VisitDiary()),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Os teus dados são guardados neste dispositivo, sem conta nem sincronização.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FavouritesList extends StatelessWidget {
  const FavouritesList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries.where((e) => e.activity.isFavorite).toList();
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Guarda os teus tronos preferidos com o coração. ♥'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) => WcCard(
        entry: entries[index],
        toggleFavorite: () => state.toggleFavorite(entries[index].bathroom.id),
        onTap: () =>
            openCollectedBathroom(context, state, entries[index].bathroom.id),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Definições')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Aparência',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo escuro'),
                  subtitle: const Text(
                    'A tua escolha fica guardada neste dispositivo.',
                  ),
                  value: state.darkMode,
                  onChanged: (_) => state.toggleTheme(),
                ),
                const Divider(height: 32),
                Text(
                  'Dados locais',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Os teus dados são guardados neste dispositivo, sem conta nem sincronização.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
