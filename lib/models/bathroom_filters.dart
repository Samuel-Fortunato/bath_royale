import 'package:bath_royale/models/bathroom_entry.dart';

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
  final bool Function(BathroomEntry) test;
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
    test: (b) => b.personalReview == null,
    exclusiveGroup: "reviewedGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.reviewed,
    label: "💩 Já avaliadas",
    test: (b) => b.personalReview != null,
    exclusiveGroup: "reviewedGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.goodRating,
    label: "✨ Avaliação positiva",
    test: (b) => (b.personalReview?.rating ?? -1) >= 4,
    exclusiveGroup: "ratingGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.badRating,
    label: "🤢 Avaliação negativa",
    test: (b) => b.personalReview != null && b.personalReview!.rating <= 2,
    exclusiveGroup: "ratingGroup",
  ),
  BathroomFilter(
    id: BathroomFilterID.confy,
    label: "🛋️ Confortável",
    test: (b) => (b.personalReview?.comfort ?? -1) >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.instagramable,
    label: "📸 Instagramável",
    test: (b) => (b.personalReview?.aesthetics ?? -1) >= 3,
  ),
  BathroomFilter(
    id: BathroomFilterID.favourite,
    label: "⭐ Favoritos",
    test: (b) => b.activity.isFavorite,
  ),
];
