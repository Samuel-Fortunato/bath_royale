import 'package:bath_royale/models/bathroom_entry.dart';

enum BathroomFilterID {
  notReviewed,
  reviewed,
  goodRating,
  badRating,
  confy,
  instagramable,
  clean,
  paper,
  noPaper,
  official,
  community,
  favourite,
  visited,
  undiscovered,
}

class BathroomFilter {
  final BathroomFilterID id;
  final String label;
  final bool Function(BathroomEntry) test;
  final String? exclusiveGroup;
  final bool personal;
  const BathroomFilter({
    required this.id,
    required this.label,
    required this.test,
    this.exclusiveGroup,
    this.personal = false,
  });
}

final List<BathroomFilter> bathroomFilters = [
  BathroomFilter(
    id: BathroomFilterID.goodRating,
    label: '★ 4 ou mais',
    test: (b) => (b.communityRating ?? -1) >= 4,
    exclusiveGroup: 'rating',
  ),
  BathroomFilter(
    id: BathroomFilterID.badRating,
    label: '★ 2 ou menos',
    test: (b) => b.communityRating != null && b.communityRating! <= 2,
    exclusiveGroup: 'rating',
  ),
  BathroomFilter(
    id: BathroomFilterID.reviewed,
    label: 'Com avaliações',
    test: (b) => b.reviewCount > 0,
    exclusiveGroup: 'reviews',
  ),
  BathroomFilter(
    id: BathroomFilterID.notReviewed,
    label: 'Sem avaliações',
    test: (b) => b.reviewCount == 0,
    exclusiveGroup: 'reviews',
  ),
  BathroomFilter(
    id: BathroomFilterID.clean,
    label: '🌸 Limpa',
    test: (b) => (b.mean((r) => r.hygiene) ?? -1) >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.confy,
    label: '🛋️ Confortável',
    test: (b) => (b.mean((r) => r.comfort) ?? -1) >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.instagramable,
    label: '📸 Instagramável',
    test: (b) => (b.mean((r) => r.aesthetics) ?? -1) >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.paper,
    label: '🧻 Papel suficiente',
    exclusiveGroup: 'paper',
    test: (b) => (b.mean((r) => r.paperAvailability) ?? -1) >= 2,
  ),
  BathroomFilter(
    id: BathroomFilterID.noPaper,
    label: '❌ Sem papel',
    exclusiveGroup: 'paper',
    test: (b) => (b.mean((r) => r.paperAvailability) ?? -1) == 0,
  ),
  BathroomFilter(
    id: BathroomFilterID.official,
    label: 'Oficial',
    test: (b) => b.bathroom.classification == 'official',
    exclusiveGroup: 'classification',
  ),
  BathroomFilter(
    id: BathroomFilterID.community,
    label: 'Comunidade',
    test: (b) => b.bathroom.classification == 'community',
    exclusiveGroup: 'classification',
  ),
  BathroomFilter(
    id: BathroomFilterID.visited,
    label: 'Visitadas',
    test: (b) => b.activity.visitCount > 0,
    exclusiveGroup: 'discovery',
    personal: true,
  ),
  BathroomFilter(
    id: BathroomFilterID.undiscovered,
    label: 'Por descobrir',
    test: (b) => b.activity.visitCount == 0,
    exclusiveGroup: 'discovery',
    personal: true,
  ),
  BathroomFilter(
    id: BathroomFilterID.favourite,
    label: '♥ Favoritos',
    test: (b) => b.activity.isFavorite,
    personal: true,
  ),
];
