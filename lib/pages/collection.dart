import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';
import 'experience_details.dart';
import '../widgets/bathroom_identity.dart';

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
        state.visibleVisits
            .where((v) => v.userId == state.currentUserId)
            .length,
        'Visitas',
      ),
      (
        state.visibleReviews
            .where((r) => r.authorId == state.currentUserId)
            .length,
        'Avaliações',
      ),
      (entries.where((e) => e.activity.isFavorite).length, 'Favoritos'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            includeDiscoveries ||
                constraints.maxWidth /
                        MediaQuery.textScalerOf(context).scale(1) <
                    250
            ? 2
            : 3;
        return Wrap(
          runSpacing: 16,
          children: [
            for (final stat in stats)
              SizedBox(
                width: constraints.maxWidth / columns,
                child: Column(
                  children: [
                    Icon(
                      switch (stat.$2) {
                        'Visitas' => Icons.explore,
                        'Avaliações' => Icons.star_rounded,
                        'Favoritos' => Icons.favorite,
                        _ => Icons.auto_awesome,
                      },
                      color: switch (stat.$2) {
                        'Avaliações' => ratingGold(context),
                        'Favoritos' => Theme.of(context).colorScheme.tertiary,
                        _ => Theme.of(context).colorScheme.primary,
                      },
                    ),
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
                        Row(
                          children: [
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: entries.isEmpty
                                          ? 0
                                          : discovered / entries.length,
                                      strokeWidth: 6,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                  const Text(
                                    '🧭',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontFamilyFallback: ['Noto Color Emoji'],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                '$discovered / ${entries.length}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                          ],
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
      return Center(
        child: Text(
          state.communityEnabled
              ? 'Ainda não há tronos guardados. Atualiza o catálogo no Explorar.'
              : 'O catálogo local ainda não tem tronos.',
        ),
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
                                    : BathroomIdentity.colors(
                                        context,
                                        entry.bathroom,
                                      ).secondaryContainer.withValues(
                                        alpha: .25,
                                      ),
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
                                        Center(
                                          child: count == 0
                                              ? Container(
                                                  width: 64,
                                                  height: 64,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '?',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.headlineLarge,
                                                  ),
                                                )
                                              : BathroomIdentity(
                                                  bathroom: entry.bathroom,
                                                  size: 64,
                                                ),
                                        ),
                                        const SizedBox(height: 8),
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
        state.visibleVisits
            .where((v) => v.userId == state.currentUserId)
            .toList()
          ..sort((a, b) {
            final order = b.visitedAt.compareTo(a.visitedAt);
            return order != 0 ? order : b.id.compareTo(a.id);
          });
    final bathrooms = {for (final b in state.visibleBathrooms) b.id: b};
    final reviews = {for (final r in state.visibleReviews) r.visitId: r};
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
                child: Row(
                  children: [
                    Icon(
                      Icons.today,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      diaryLabel(date),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: BathroomIdentity(bathroom: bathrooms[visit.bathroomId]!),
              title: Text(bathrooms[visit.bathroomId]!.name),
              subtitle: Text(
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${review == null ? '' : ' · ${review.rating.toStringAsFixed(1).replaceAll('.', ',')} / 5 ★'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: state,
                    child: ExperienceDetailsPage(visitId: visit.id),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

String diaryLabel(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final current = DateTime(today.year, today.month, today.day);
  if (day == current) return 'Hoje';
  if (day == DateTime(current.year, current.month, current.day - 1)) {
    return 'Ontem';
  }
  return diaryDay(local);
}
