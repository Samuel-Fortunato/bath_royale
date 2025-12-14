import 'package:bath_royale/models/bathroom.dart';

// TODO: Solve rating based filters on not reviewed WC's
enum BathroomFilterID {
  notReviewed,
  reviewed,
  goodRating,
  badRating,
  confy,
  instagramable,
  favourite,
}

class BathroomFilter {
  final BathroomFilterID id;
  final String label;
  final bool Function(Bathroom) test;
  final String? exclusiveGroup;

  const BathroomFilter({
    required this.id,
    required this.label,
    required this.test,
    this.exclusiveGroup,
  });
}

final List<BathroomFilter> bathroomFilters = [
  BathroomFilter(
    id: BathroomFilterID.notReviewed,
    label: "🚽 Não avaliadas",
    test: (b) => !b.reviewed,
    exclusiveGroup: "reviewedGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.reviewed,
    label: "💩 Já avaliadas",
    test: (b) => b.reviewed,
    exclusiveGroup: "reviewedGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.goodRating,
    label: "✨ Avaliação positiva",
    test: (b) => b.reviewed && b.rating >= 4,
    exclusiveGroup: "ratingGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.badRating,
    label: "🤢 Avaliação negativa",
    test: (b) => b.reviewed && b.rating <= 2,
    exclusiveGroup: "ratingGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.confy,
    label: "🛋️ Confortável",
    test: (b) => b.reviewed && b.confort >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.instagramable,
    label: "📸 Instagramável",
    test: (b) => b.reviewed && b.aesthetics >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.favourite,
    label: "⭐ Favoritos",
    test: (b) => b.isFavorite.value,
  ),
];
