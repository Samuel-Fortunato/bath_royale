import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ranking.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'A realeza dos tronos 👑',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Comunidade')),
                ButtonSegment(value: true, label: Text('Pessoal')),
              ],
              selected: {_personal},
              onSelectionChanged: (v) => setState(() => _personal = v.single),
            ),
            const SizedBox(height: 12),
            Text(
              _personal
                  ? 'Média de todas as tuas avaliações por casa de banho. No Explorar, a nota pessoal é a da tua visita avaliada mais recente.'
                  : 'Média de todas as avaliações locais da comunidade.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final metric in RankingMetric.values)
                  ChoiceChip(
                    label: Text(metric.label),
                    selected: _metric == metric,
                    onSelected: (_) => setState(() => _metric = metric),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _worst = !_worst),
                icon: Icon(_worst ? Icons.south : Icons.north),
                label: Text(_worst ? 'Piores primeiro' : 'Melhores primeiro'),
              ),
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda sem avaliações para este ranking. Os tronos aguardam histórias. 🚽',
                ),
              ),
            for (var i = 0; i < rows.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(rows[i].bathroom.name),
                  subtitle: Text(
                    '${rows[i].count} ${rows[i].count == 1 ? 'avaliação' : 'avaliações'}',
                  ),
                  trailing: Text(
                    '${rows[i].score.toStringAsFixed(1)} / ${_metric.maximum}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: state,
                        child: BathroomDetailsPage(
                          bathroomId: rows[i].bathroom.id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
