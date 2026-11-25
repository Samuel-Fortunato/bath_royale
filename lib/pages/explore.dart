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

  List<BathroomFilter> quickFilters() {
    final visible = visibleFilters();
    return [
      ...visible.where(activeFilters.contains),
      ...visible.where(
        (f) =>
            !activeFilters.contains(f) &&
            (f.id == BathroomFilterID.favourite ||
                f.id == BathroomFilterID.reviewed ||
                f.id == BathroomFilterID.notReviewed),
      ),
    ];
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
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Procurar um trono',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar pesquisa',
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    setState(() => _search.clear()),
                              ),
                      ),
                    ),
                  ),
                  PopupMenuButton<BathroomSort>(
                    tooltip: 'Ordenar por',
                    icon: const Icon(Icons.sort),
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: BathroomSort.name,
                        child: Text('Nome (A–Z)'),
                      ),
                      PopupMenuItem(
                        value: BathroomSort.community,
                        child: Text('Avaliação da comunidade'),
                      ),
                      PopupMenuItem(
                        value: BathroomSort.personal,
                        child: Text('A minha avaliação'),
                      ),
                      PopupMenuItem(
                        value: BathroomSort.latestVisit,
                        child: Text('Última visita (mais recente)'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Filtros',
                    icon: Badge(
                      isLabelVisible: activeFilters.isNotEmpty,
                      label: Text('${activeFilters.length}'),
                      child: const Icon(Icons.tune),
                    ),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (sheetContext) => StatefulBuilder(
                        builder: (context, refresh) => SafeArea(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Filtros',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Os filtros de avaliação usam as tuas experiências.',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final filter in visibleFilters())
                                      FilterChip(
                                        label: Text(filter.label),
                                        selected: activeFilters.contains(
                                          filter,
                                        ),
                                        onSelected: (selected) {
                                          _toggleFilter(filter, selected);
                                          refresh(() {});
                                        },
                                      ),
                                  ],
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.pop(sheetContext),
                                    child: const Text('Ver resultados'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: quickFilters().length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final filter = quickFilters()[index];
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
