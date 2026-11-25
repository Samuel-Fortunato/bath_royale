import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visits =
        state.visits.where((v) => v.userId == state.currentUserId).toList()
          ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    final favourites = state.entries
        .where((e) => e.activity.isFavorite)
        .toList();
    void open(String id) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: BathroomDetailsPage(bathroomId: id),
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'O teu canto do reino 🚽',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Perfil local neste dispositivo. Os teus dados são guardados aqui, sem conta nem sincronização.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('${visits.length} visitas')),
                Chip(
                  label: Text(
                    '${state.reviews.where((r) => r.authorId == state.currentUserId).length} avaliações',
                  ),
                ),
              ],
            ),
            if (visits.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('A tua última visita'),
                  subtitle: Text(
                    '${state.allBathrooms.firstWhere((b) => b.id == visits.first.bathroomId).name}\n${reviewDate(visits.first.visitedAt)}',
                  ),
                  onTap: () => open(visits.first.bathroomId),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Os teus favoritos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (favourites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Guarda os teus tronos preferidos com o coração. ♥',
                ),
              ),
            for (final entry in favourites)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.favorite),
                  title: Text(entry.bathroom.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(entry.bathroom.id),
                ),
              ),
          ],
        ),
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
                SwitchListTile(
                  title: const Text('Modo escuro'),
                  value: state.darkMode,
                  onChanged: (_) => state.toggleTheme(),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Os teus dados são guardados neste dispositivo.'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
