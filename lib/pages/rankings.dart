import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ranking.dart';
import '../state/app_state.dart';
import 'collection.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});
  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  bool _personal = false, _worst = false;
  RankingMetric _metric = RankingMetric.overall;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rows = rankBathrooms(
      state.allBathrooms,
      state.reviews,
      _metric,
      userId: _personal ? state.currentUserId : null,
      worst: _worst,
    );
    return DefaultTabController(
      length: RankingMetric.values.length,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Comunidade')),
                    ButtonSegment(value: true, label: Text('Pessoal')),
                  ],
                  selected: {_personal},
                  onSelectionChanged: (v) =>
                      setState(() => _personal = v.single),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                onTap: (index) =>
                    setState(() => _metric = RankingMetric.values[index]),
                tabs: [
                  for (final metric in RankingMetric.values)
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
              if (_personal)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Inclui todas as tuas avaliações por trono. No Explorar, vês a tua experiência avaliada mais recente.',
                    style: Theme.of(context).textTheme.bodySmall,
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
