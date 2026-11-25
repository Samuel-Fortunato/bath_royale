import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.entries
        .where((entry) => entry.activity.visitCount > 0)
        .toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: entries.isEmpty
            ? const Text('As casas de banho que visitares aparecem aqui. 🚽')
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'A tua coleção',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  for (final entry in entries)
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.collections_bookmark_outlined,
                        ),
                        title: Text(entry.bathroom.name),
                        subtitle: Text(
                          '${entry.activity.visitCount} ${entry.activity.visitCount == 1 ? 'visita' : 'visitas'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: state,
                              child: BathroomDetailsPage(
                                bathroomId: entry.bathroom.id,
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
