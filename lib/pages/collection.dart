import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries;
    final discovered = entries.where((e) => e.activity.visitCount > 0).length;
    final visits =
        state.visits.where((v) => v.userId == state.currentUserId).toList()
          ..sort((a, b) {
            final order = b.visitedAt.compareTo(a.visitedAt);
            return order != 0 ? order : b.id.compareTo(a.id);
          });
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'A tua coleção 🚽',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('$discovered de ${entries.length} tronos descobertos'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: entries.isEmpty ? 0 : discovered / entries.length,
              semanticsLabel: 'Exploração do catálogo local',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.explore_outlined),
                  label: Text('$discovered descobertos'),
                ),
                Chip(
                  avatar: const Icon(Icons.history),
                  label: Text('${visits.length} visitas'),
                ),
                Chip(
                  avatar: const Icon(Icons.rate_review_outlined),
                  label: Text(
                    '${state.reviews.where((r) => r.authorId == state.currentUserId).length} avaliações',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.favorite_outline),
                  label: Text(
                    '${entries.where((e) => e.activity.isFavorite).length} favoritos',
                  ),
                ),
              ],
            ),
            if (discovered == 0)
              const Text('As casas de banho que visitares aparecem aqui. 🚽'),
            for (final entry in entries)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry.activity.visitCount == 0
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      entry.activity.visitCount == 0
                          ? Icons.travel_explore
                          : Icons.wc,
                    ),
                  ),
                  title: Text(entry.bathroom.name),
                  subtitle: Text(
                    entry.activity.visitCount == 0
                        ? 'Por descobrir'
                        : '${entry.activity.visitCount} ${entry.activity.visitCount == 1 ? 'visita' : 'visitas'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(entry.bathroom.id),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Diário de exploração',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (visits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('O teu diário começa na próxima visita.'),
              ),
            for (final visit in visits)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  entries
                      .firstWhere((e) => e.bathroom.id == visit.bathroomId)
                      .bathroom
                      .name,
                ),
                subtitle: Text(reviewDate(visit.visitedAt)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(visit.bathroomId),
              ),
          ],
        ),
      ),
    );
  }
}
