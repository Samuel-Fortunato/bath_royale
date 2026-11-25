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
          (other) =>
              other.id != BathroomFilterID.favourite &&
              other.exclusiveGroup != 'discoveryGroup' &&
              other.id != BathroomFilterID.reviewed &&
              other.id != BathroomFilterID.notReviewed,
        );
      }
      if (filter.id != BathroomFilterID.favourite &&
          filter.exclusiveGroup != 'discoveryGroup' &&
          filter.exclusiveGroup != 'reviewedGroup') {
        activeFilters.removeWhere(
          (other) => other.id == BathroomFilterID.notReviewed,
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

  Future<void> _showFilters() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, refresh) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtros',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Os filtros de avaliação usam as tuas experiências.',
                    ),
                    for (final group in const {
                      'Descoberta': [
                        BathroomFilterID.visited,
                        BathroomFilterID.undiscovered,
                      ],
                      'Avaliação pessoal': [
                        BathroomFilterID.notReviewed,
                        BathroomFilterID.reviewed,
                        BathroomFilterID.goodRating,
                        BathroomFilterID.badRating,
                      ],
                      'Características pessoais': [
                        BathroomFilterID.confy,
                        BathroomFilterID.instagramable,
                      ],
                      'Favoritos': [BathroomFilterID.favourite],
                    }.entries) ...[
                      const SizedBox(height: 16),
                      Text(
                        group.key,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final filter in bathroomFilters.where(
                            (f) => group.value.contains(f.id),
                          ))
                            FilterChip(
                              label: Text(filter.label),
                              selected: activeFilters.contains(filter),
                              onSelected: (selected) {
                                _toggleFilter(filter, selected);
                                refresh(() {});
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => activeFilters.clear());
                      refresh(() {});
                    },
                    child: const Text('Limpar filtros'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Ver resultados'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
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
                              filled: true,
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
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
                        IconButton(
                          tooltip: 'Filtros',
                          icon: Badge(
                            isLabelVisible: activeFilters.isNotEmpty,
                            label: Text('${activeFilters.length}'),
                            child: const Icon(Icons.tune),
                          ),
                          onPressed: _showFilters,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16, top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PopupMenuButton<BathroomSort>(
                        tooltip: 'Ordenar por',
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
                            child: Text('Última experiência pessoal'),
                          ),
                          PopupMenuItem(
                            value: BathroomSort.latestVisit,
                            child: Text('Última visita (mais recente)'),
                          ),
                        ],
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort, size: 18),
                              const SizedBox(width: 6),
                              Text(switch (_sort) {
                                BathroomSort.name => 'A–Z',
                                BathroomSort.community => 'Comunidade',
                                BathroomSort.personal => 'Pessoal',
                                BathroomSort.latestVisit => 'Recentes',
                              }),
                              const Icon(Icons.expand_more, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (activeFilters.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final filter in activeFilters)
                            InputChip(
                              label: Text(filter.label),
                              onDeleted: () => _toggleFilter(filter, false),
                              deleteButtonTooltipMessage:
                                  'Remover ${filter.label}',
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      if (activeFilters.isNotEmpty || query.isNotEmpty)
                        Text('${filteredWCs.length} resultados'),
                      if (activeFilters.isNotEmpty || _search.text.isNotEmpty)
                        TextButton(
                          onPressed: _clear,
                          child: const Text('Limpar pesquisa e filtros'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (filteredWCs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    appState.entries.isEmpty
                        ? 'Ainda não há tronos. Usa + para criar o primeiro! 🚽'
                        : 'Nenhum trono à vista. Experimenta limpar a pesquisa e os filtros. 🚽',
                  ),
                ),
              )
            else
              SliverList.builder(
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
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }
}
