import '../models/bathroom_sort.dart';
import '../models/tag_presentation.dart';
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
  String? _tag;
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
    _tag = null;
  });

  List<BathroomEntry> applyFilters(List<BathroomEntry> list) {
    for (final filter in bathroomFilters) {
      if (activeFilters.contains(filter) &&
          (!filter.personal || !context.read<AppState>().readOnly)) {
        list = list.where(filter.test).toList();
      }
    }
    return _tag == null
        ? list
        : list
              .where(
                (b) =>
                    b.communityTags.any((t) => TagPresentation.key(t) == _tag),
              )
              .toList();
  }

  void _toggleFilter(BathroomFilter filter, bool selected) {
    if (selected) {
      if (filter.id == BathroomFilterID.notReviewed) {
        activeFilters.removeWhere(
          (f) =>
              !f.personal &&
              ![
                BathroomFilterID.official,
                BathroomFilterID.community,
              ].contains(f.id),
        );
        _tag = null;
      } else if (!filter.personal &&
          ![
            BathroomFilterID.official,
            BathroomFilterID.community,
            BathroomFilterID.reviewed,
          ].contains(filter.id)) {
        activeFilters.removeWhere((f) => f.id == BathroomFilterID.notReviewed);
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
                    for (final group in const {
                      'Avaliações da comunidade': [
                        BathroomFilterID.goodRating,
                        BathroomFilterID.badRating,
                        BathroomFilterID.reviewed,
                        BathroomFilterID.notReviewed,
                      ],
                      'Características': [
                        BathroomFilterID.clean,
                        BathroomFilterID.confy,
                        BathroomFilterID.instagramable,
                        BathroomFilterID.paper,
                        BathroomFilterID.noPaper,
                      ],
                      'Tronos': [
                        BathroomFilterID.official,
                        BathroomFilterID.community,
                      ],
                    }.entries) ...[
                      const SizedBox(height: 12),
                      Text(
                        group.key,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final f in bathroomFilters.where(
                            (f) => group.value.contains(f.id),
                          ))
                            FilterChip(
                              label: Text(f.label),
                              selected: activeFilters.contains(f),
                              onSelected: (v) {
                                _toggleFilter(f, v);
                                refresh(() {});
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _tag,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Etiqueta da comunidade',
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Todas')),
                        for (final t in {
                          for (final b in context.read<AppState>().entries)
                            for (final t in b.communityTags)
                              TagPresentation.key(t): t,
                        }.entries)
                          DropdownMenuItem(
                            value: t.key,
                            child: Text(
                              TagPresentation.display(t.value),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _tag = v == '' ? null : v);
                        refresh(() {});
                      },
                    ),
                    if (!context.read<AppState>().readOnly)
                      ExpansionTile(
                        title: const Text('Os meus tronos'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final f in bathroomFilters.where(
                                (f) => f.personal,
                              ))
                                FilterChip(
                                  label: Text(f.label),
                                  selected: activeFilters.contains(f),
                                  onSelected: (v) {
                                    _toggleFilter(f, v);
                                    refresh(() {});
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
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
                      setState(() {
                        activeFilters.clear();
                        _tag = null;
                      });
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
        child: RefreshIndicator(
          onRefresh: () => appState.community?.refresh() ?? Future.value(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (appState.community?.error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Sem ligação. A mostrar os tronos guardados.',
                        ),
                      ),
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
                              isLabelVisible:
                                  (activeFilters.isNotEmpty || _tag != null),
                              label: Text(
                                '${activeFilters.length + (_tag == null ? 0 : 1)}',
                              ),
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
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: BathroomSort.name,
                              child: Text('Nome (A–Z)'),
                            ),
                            PopupMenuItem(
                              value: BathroomSort.community,
                              child: Text('Avaliação da comunidade'),
                            ),
                            if (!appState.readOnly)
                              const PopupMenuItem(
                                value: BathroomSort.personal,
                                child: Text('Última experiência pessoal'),
                              ),
                            if (!appState.readOnly)
                              const PopupMenuItem(
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
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        if ((activeFilters.isNotEmpty || _tag != null) ||
                            query.isNotEmpty)
                          Text('${filteredWCs.length} resultados'),
                        if ((activeFilters.isNotEmpty || _tag != null) ||
                            _search.text.isNotEmpty)
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
                          ? (appState.communityEnabled
                                ? 'Ainda não há tronos disponíveis. Volta a tentar com ligação à internet. 🚽'
                                : 'Ainda não há tronos para descobrir. 🚽')
                          : 'Nenhum trono à vista. Experimenta limpar a pesquisa e os filtros. 🚽',
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: filteredWCs.length,
                  itemBuilder: (context, i) => WcCard(
                    entry: filteredWCs[i],
                    showPersonal: !appState.readOnly,
                    toggleFavorite:
                        appState.readOnly ||
                            !appState.isAvailable(filteredWCs[i].bathroom.id)
                        ? null
                        : () => appState.toggleFavorite(
                            filteredWCs[i].bathroom.id,
                          ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: 'bathroom'),
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
      ),
    );
  }
}
