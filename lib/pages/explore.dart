import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_filters.dart';
import 'package:bath_royale/widgets/wc_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bath_royale/state/app_state.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  Set<BathroomFilter> activeFilters = {};

  List<Bathroom> applyFilters(List<Bathroom> list) {
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
    final filteredWCs = applyFilters(appState.allBathrooms);

    return Column(
      children: [
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
        Expanded(
          child: ListView.builder(
            itemCount: filteredWCs.length,
            itemBuilder: (context, i) => WcCard(
              bathroom: filteredWCs[i],
              onTap: () {},
              /* toggleFavorite: () {
                filteredWCs[i].toggleFavorite();
              }, */
            ),
          ),
        ),
      ],
    );
  }
}
