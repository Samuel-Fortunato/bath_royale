import 'private_synchronization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'authentication.dart';
import '../widgets/wc_card.dart';
import 'collection.dart';
import '../models/ranking.dart';
import '../models/bathroom.dart';
import '../widgets/bathroom_identity.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Widget _highlight(
    BuildContext context,
    AppState state,
    Bathroom bathroom,
    String title,
    String detail,
  ) => Card(
    color: BathroomIdentity.colors(
      context,
      bathroom,
    ).secondaryContainer.withValues(alpha: .3),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openCollectedBathroom(context, state, bathroom.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BathroomIdentity(bathroom: bathroom, size: 36),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(bathroom.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

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
            if (state.synchronization != null)
              PrivateSynchronizationCard(sync: state.synchronization!),
            Card(
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('A minha conta'),
                subtitle: const Text('Sessão e segurança · email privado'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AuthenticationPage(
                      canTransition: !state.hasUncommittedWork,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          child: Icon(Icons.person_outline, size: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'O teu perfil',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const Text('Explorador local'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const LocalStatistics(includeDiscoveries: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide =
                    constraints.maxWidth >= 340 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 18;
                final highlights = <Widget>[
                  if (visited.isNotEmpty)
                    _highlight(
                      context,
                      state,
                      visited.first.bathroom,
                      'O teu trono habitual',
                      '${visited.first.activity.visitCount} visitas',
                    ),
                  if (rated.isNotEmpty)
                    _highlight(
                      context,
                      state,
                      rated.first.bathroom,
                      'O teu favorito nas avaliações',
                      '${rated.first.score.toStringAsFixed(1).replaceAll('.', ',')} / 5\nMédia das tuas ${rated.first.count} avaliações',
                    ),
                ];
                return sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final card in highlights) Expanded(child: card),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: highlights,
                      );
              },
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'A sincronização privada é opcional e pode ser gerida no Perfil. Os dados antigos e os exemplos fictícios estão preservados em separado.',
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
                  'A sincronização privada é opcional e pode ser gerida no Perfil. Os dados antigos e os exemplos fictícios estão preservados em separado.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
