import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ranking.dart';
import '../state/app_state.dart';
import 'collection.dart';
import '../widgets/bathroom_identity.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});
  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  bool _personal = false, _worst = false, _byCategory = false;
  RankingMetric _category = RankingMetric.hygiene;
  RankingMetric get _metric => _byCategory ? _category : RankingMetric.overall;

  Widget _modeTile(bool category, String label, IconData icon) {
    final selected = _byCategory == category;
    final scheme = Theme.of(context).colorScheme;
    final accent = category ? scheme.primary : ratingGold(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: selected ? accent : scheme.onSurfaceVariant,
          backgroundColor: selected
              ? accent.withValues(alpha: .12)
              : scheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => setState(() => _byCategory = category),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 6),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows = rankBathrooms(
      state.visibleBathrooms,
      !_personal && state.communityEnabled
          ? state.community!.reviews
          : state.visibleReviews,
      _metric,
      userId: _personal ? state.currentUserId : null,
      worst: _worst,
      bathroomIdentity: state.sharedIdentity,
    );
    return DefaultTabController(
      length: 4,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!state.readOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SegmentedButton<bool>(
                    showSelectedIcon:
                        MediaQuery.sizeOf(context).width >= 360 ||
                        MediaQuery.textScalerOf(context).scale(14) <= 18,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Comunidade')),
                      ButtonSegment(value: true, label: Text('Pessoal')),
                    ],
                    selected: {_personal},
                    onSelectionChanged: (v) =>
                        setState(() => _personal = v.single),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _modeTile(
                        false,
                        'Geral',
                        Icons.emoji_events_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _modeTile(true, 'Por categoria', Icons.bar_chart),
                    ),
                  ],
                ),
              ),
              if (_byCategory)
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) => setState(
                    () => _category = RankingMetric.values[index + 1],
                  ),
                  tabs: [
                    for (final metric in RankingMetric.values.skip(1))
                      Tab(text: metric.label),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(
                      _personal
                          ? 'Média das tuas avaliações'
                          : state.communityEnabled
                          ? 'Média das avaliações publicadas'
                          : 'Média das avaliações locais',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _worst = !_worst),
                      icon: Icon(_worst ? Icons.south : Icons.north, size: 18),
                      label: Text(_worst ? 'Piores' : 'Melhores'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Ainda sem avaliações para este ranking. Os tronos aguardam histórias. 🚽',
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const PageStorageKey('ranking-rows'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          if (!_worst && index < 3) {
                            if (index > 0) return const SizedBox.shrink();
                            return RankingPodium(
                              rows: rows.take(3).toList(),
                              metric: _metric,
                            );
                          }
                          return InkWell(
                            onTap: () => openCollectedBathroom(
                              context,
                              state,
                              row.bathroom.id,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '${index + 1}'.padLeft(2, '0'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ),
                                  BathroomIdentity(
                                    bathroom: row.bathroom,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row.bathroom.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${row.count} ${row.count == 1 ? 'avaliação' : 'avaliações'}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 8),
                                        LinearProgressIndicator(
                                          value: row.score / _metric.maximum,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${row.score.toStringAsFixed(1).replaceAll('.', ',')} / ${_metric.maximum}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Leading positions wrap into a vertical podium when text needs more room.
class RankingPodium extends StatelessWidget {
  const RankingPodium({super.key, required this.rows, required this.metric});
  final List<RankedBathroom> rows;
  final RankingMetric metric;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final state = context.read<AppState>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 350 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        Widget place(int index) {
          final row = rows[index];
          final scheme = ColorScheme.fromSeed(
            seedColor: [Colors.amber, Colors.blueGrey, Colors.brown][index],
            brightness: Theme.of(context).brightness,
          );
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final name = Tooltip(
            message: row.bathroom.name,
            child: Semantics(
              label: row.bathroom.name,
              child: ExcludeSemantics(
                child: Text(
                  row.bathroom.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: stacked ? TextAlign.start : TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          );
          final score = Text(
            '${row.score.toStringAsFixed(1).replaceAll('.', ',')} / ${metric.maximum}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: ratingGold(context)),
          );
          return Card(
            key: ValueKey('podium-${index + 1}'),
            color: scheme.secondaryContainer.withValues(
              alpha: index == 0 ? .65 : .3,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  openCollectedBathroom(context, state, row.bathroom.id),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: stacked
                    ? Row(
                        children: [
                          Text(
                            ['🥇', '🥈', '🥉'][index],
                            style: const TextStyle(
                              fontSize: 24,
                              fontFamilyFallback: ['Noto Color Emoji'],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: name),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              score,
                              Text(
                                '${row.count} aval.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ['🥇', '🥈', '🥉'][index],
                            semanticsLabel: '${index + 1}º lugar',
                            style: const TextStyle(
                              fontSize: 24,
                              fontFamilyFallback: ['Noto Color Emoji'],
                            ),
                          ),
                          BathroomIdentity(bathroom: row.bathroom, size: 40),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 42 * textScale,
                            child: Align(
                              alignment: Alignment.center,
                              child: name,
                            ),
                          ),
                          const SizedBox(height: 4),
                          score,
                          Text(
                            '${row.count} aval.',
                            semanticsLabel: '${row.count} avaliações',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),
          );
        }

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < rows.length; i++) place(i)],
          );
        }
        final order = [if (rows.length > 1) 1, 0, if (rows.length > 2) 2];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in order)
              Expanded(
                child: Padding(padding: EdgeInsets.zero, child: place(i)),
              ),
          ],
        );
      },
    );
  }
}
