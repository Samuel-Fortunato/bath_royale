import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

void openCollectedBathroom(BuildContext context, AppState state, String id) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider.value(
        value: state,
        child: BathroomDetailsPage(bathroomId: id),
      ),
    ),
  );
}

/// Equal-width, wrapping statistics shared by the collection and local profile.
class LocalStatistics extends StatelessWidget {
  const LocalStatistics({super.key, this.includeDiscoveries = false});
  final bool includeDiscoveries;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries;
    final stats = <(int, String)>[
      if (includeDiscoveries)
        (entries.where((e) => e.activity.visitCount > 0).length, 'Descobertas'),
      (
        state.visits.where((v) => v.userId == state.currentUserId).length,
        'Visitas',
      ),
      (
        state.reviews.where((r) => r.authorId == state.currentUserId).length,
        'Avaliações',
      ),
      (entries.where((e) => e.activity.isFavorite).length, 'Favoritos'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = includeDiscoveries ? 2 : 3;
        return Wrap(
          runSpacing: 16,
          children: [
            for (final stat in stats)
              SizedBox(
                width: constraints.maxWidth / columns,
                child: Column(
                  children: [
                    Text(
                      '${stat.$1}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      stat.$2,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(letterSpacing: 0),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries;
    final discovered = entries.where((e) => e.activity.visitCount > 0).length;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$discovered / ${entries.length}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Text('Tronos descobertos'),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: entries.isEmpty
                              ? 0
                              : discovered / entries.length,
                          semanticsLabel:
                              'Exploração do catálogo local: $discovered de ${entries.length} tronos descobertos',
                        ),
                        const SizedBox(height: 16),
                        const LocalStatistics(),
                      ],
                    ),
                  ),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Tronos'),
                  Tab(text: 'Diário'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [CollectibleCatalogue(), VisitDiary()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectibleCatalogue extends StatelessWidget {
  const CollectibleCatalogue({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries;
    if (entries.isEmpty) {
      return const Center(
        child: Text('O catálogo local ainda não tem tronos.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = ((constraints.maxWidth - 32) / (145 * scale))
            .floor()
            .clamp(1, 4);
        // Lazy rows grow to fit full names and large text, without fixed card heights.
        return ListView.builder(
          key: const PageStorageKey('collectible-catalogue'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: (entries.length / columns).ceil(),
          itemBuilder: (context, row) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: row * columns + column >= entries.length
                        ? const SizedBox.shrink()
                        : Builder(
                            builder: (context) {
                              final entry = entries[row * columns + column];
                              final count = entry.activity.visitCount;
                              return Card(
                                color: count == 0
                                    ? Theme.of(context).colorScheme.surface
                                    : null,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => openCollectedBathroom(
                                    context,
                                    state,
                                    entry.bathroom.id,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          count == 0
                                              ? '○ Por descobrir'
                                              : '✓ Descoberta',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelMedium,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          entry.bathroom.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          count == 0
                                              ? 'Sem visitas'
                                              : '$count ${count == 1 ? 'visita' : 'visitas'}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String diaryDay(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

/// Shared lazy personal history, grouped by local (not UTC) calendar date.
class VisitDiary extends StatelessWidget {
  const VisitDiary({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visits =
        state.visits.where((v) => v.userId == state.currentUserId).toList()
          ..sort((a, b) {
            final order = b.visitedAt.compareTo(a.visitedAt);
            return order != 0 ? order : b.id.compareTo(a.id);
          });
    final names = {for (final b in state.allBathrooms) b.id: b.name};
    final reviews = {for (final r in state.reviews) r.visitId: r};
    if (visits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('O teu diário começa na próxima visita.'),
        ),
      );
    }
    return ListView.builder(
      key: const PageStorageKey('visit-diary'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: visits.length,
      itemBuilder: (context, index) {
        final visit = visits[index];
        final date = visit.visitedAt.toLocal();
        final day = diaryDay(date);
        final review = reviews[visit.id];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index == 0 || diaryDay(visits[index - 1].visitedAt) != day)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(day, style: Theme.of(context).textTheme.titleSmall),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(names[visit.bathroomId]!),
              subtitle: Text(
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${review == null ? '' : ' · ${review.rating.toStringAsFixed(1).replaceAll('.', ',')} / 5 ★'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  openCollectedBathroom(context, state, visit.bathroomId),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}
