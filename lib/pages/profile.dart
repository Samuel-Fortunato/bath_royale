import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/wc_card.dart';
import 'collection.dart';
import '../models/ranking.dart';
import '../widgets/bathroom_identity.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visited =
        state.entries.where((e) => e.activity.visitCount > 0).toList()..sort((
          a,
          b,
        ) {
          final count = b.activity.visitCount.compareTo(a.activity.visitCount);
          if (count != 0) return count;
          final name = a.bathroom.name.toLowerCase().compareTo(
            b.bathroom.name.toLowerCase(),
          );
          return name != 0 ? name : a.bathroom.id.compareTo(b.bathroom.id);
        });
    final rated = rankBathrooms(
      state.allBathrooms,
      state.reviews,
      RankingMetric.overall,
      userId: state.currentUserId,
    );
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: CircleAvatar(
                  radius: 32,
                  child: Text(
                    '🧭',
                    style: TextStyle(
                      fontSize: 36,
                      fontFamilyFallback: ['Noto Color Emoji'],
                    ),
                  ),
                ),
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
            if (visited.isNotEmpty)
              Card(
                child: ListTile(
                  leading: BathroomIdentity(bathroom: visited.first.bathroom),
                  title: const Text('O teu trono habitual'),
                  subtitle: Text(
                    '${visited.first.bathroom.name} · ${visited.first.activity.visitCount} visitas',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCollectedBathroom(
                    context,
                    state,
                    visited.first.bathroom.id,
                  ),
                ),
              ),
            if (rated.isNotEmpty)
              Card(
                child: ListTile(
                  leading: BathroomIdentity(bathroom: rated.first.bathroom),
                  title: const Text('O teu favorito nas avaliações'),
                  subtitle: Text(
                    '${rated.first.bathroom.name} · ${rated.first.score.toStringAsFixed(1).replaceAll('.', ',')} / 5\nMédia das tuas ${rated.first.count} avaliações',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCollectedBathroom(
                    context,
                    state,
                    rated.first.bathroom.id,
                  ),
                ),
              ),
            if (visited.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'A próxima visita pode revelar o teu trono habitual.',
                ),
              ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              title: const Text('Os meus favoritos'),
              subtitle: Text(
                '${state.entries.where((e) => e.activity.isFavorite).length} favoritos',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open('Os meus favoritos', const FavouritesList()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Definições'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: state,
                    child: const SettingsPage(),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Dados locais, sem conta nem sincronização. O protótipo inclui exemplos fictícios.',
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
                  'Dados locais, sem conta nem sincronização. O protótipo inclui exemplos fictícios.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
