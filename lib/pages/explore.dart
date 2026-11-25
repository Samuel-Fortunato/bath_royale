import '../models/bathroom_sort.dart';
import 'package:bath_royale/models/bathroom_entry.dart';
import 'package:bath_royale/models/bathroom_filters.dart';
import 'package:bath_royale/widgets/wc_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bathroom_details.dart';

import 'package:bath_royale/state/app_state.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  Set<BathroomFilter> activeFilters = {};
  final _search = TextEditingController();
  BathroomSort _sort = BathroomSort.name;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
    _search.clear();
    activeFilters.clear();
  });

  List<BathroomEntry> applyFilters(List<BathroomEntry> list) {
    for (final filter in bathroomFilters) {
      if (activeFilters.contains(filter)) {
        list = list.where(filter.test).toList();
      }
    }
    return list;
  }

  void _toggleFilter(BathroomFilter filter, bool selected) {
    if (selected) {
      if (filter.id == BathroomFilterID.notReviewed) {
        activeFilters.removeWhere(
          (other) => other.id != BathroomFilterID.favourite,
        );
      }
      if (filter.exclusiveGroup != null) {
        activeFilters.removeWhere(
          (other) => other.exclusiveGroup == filter.exclusiveGroup,
        );
      }
      setState(() {
        activeFilters.add(filter);
      });
    } else {
      setState(() {
        activeFilters.remove(filter);
      });
    }
  }

  List<BathroomFilter> visibleFilters() {
    if (activeFilters.any((f) => f.id == BathroomFilterID.notReviewed)) {
      // Apenas filtros compatíveis com 'notReviewed'
      return bathroomFilters
          .where(
            (f) =>
                f.id == BathroomFilterID.notReviewed ||
                f.id == BathroomFilterID.reviewed ||
                f.id == BathroomFilterID.favourite,
          )
          .toList();
    }
    return bathroomFilters; // todos visíveis se 'notReviewed' não estiver ativo
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final query = AppState.normalizeName(_search.text);
    final filteredWCs = sortBathrooms(
      applyFilters(appState.entries).where(
        (entry) => AppState.normalizeName(entry.bathroom.name).contains(query),
      ),
      _sort,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Pesquisar por nome',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar pesquisa',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _search.clear()),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<BathroomSort>(
                    initialValue: _sort,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: const [
                      DropdownMenuItem(
                        value: BathroomSort.name,
                        child: Text('Nome (A–Z)'),
                      ),
                      DropdownMenuItem(
                        value: BathroomSort.community,
                        child: Text('Avaliação da comunidade'),
                      ),
                      DropdownMenuItem(
                        value: BathroomSort.personal,
                        child: Text('A minha avaliação'),
                      ),
                      DropdownMenuItem(
                        value: BathroomSort.latestVisit,
                        child: Text('Última visita (mais recente)'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _sort = value!),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Os filtros de avaliação usam as tuas experiências.'),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: visibleFilters().length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final filter = visibleFilters()[index];
                  return ChoiceChip(
                    label: Text(filter.label),
                    selected: activeFilters.contains(filter),
                    onSelected: (val) => _toggleFilter(filter, val),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text('${filteredWCs.length} casas de banho'),
                if (activeFilters.isNotEmpty || _search.text.isNotEmpty)
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Limpar pesquisa e filtros'),
                  ),
              ],
            ),
            Expanded(
              child: filteredWCs.isEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        appState.entries.isEmpty
                            ? 'Ainda não há tronos. Usa + para criar o primeiro! 🚽'
                            : 'Nenhum trono à vista. Experimenta limpar a pesquisa e os filtros. 🚽',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: filteredWCs.length,
                      itemBuilder: (context, i) => WcCard(
                        entry: filteredWCs[i],
                        toggleFavorite: () =>
                            appState.toggleFavorite(filteredWCs[i].bathroom.id),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: appState,
                              child: BathroomDetailsPage(
                                bathroomId: filteredWCs[i].bathroom.id,
                              ),
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
