import 'bathroom.dart';
import 'review.dart';

enum RankingMetric {
  overall('Global', 5),
  hygiene('Higiene', 4),
  comfort('Conforto', 4),
  aesthetics('Estética', 4),
  paper('Papel', 2);

  final String label;
  final int maximum;
  const RankingMetric(this.label, this.maximum);
  double score(ReviewScores r) => switch (this) {
    overall => r.rating,
    hygiene => r.hygiene.toDouble(),
    comfort => r.comfort.toDouble(),
    aesthetics => r.aesthetics.toDouble(),
    paper => r.paperAvailability.toDouble(),
  };
}

class RankedBathroom {
  final Bathroom bathroom;
  final double score;
  final int count;
  RankedBathroom(this.bathroom, this.score, this.count);
}

List<RankedBathroom> rankBathrooms(
  Iterable<Bathroom> bathrooms,
  Iterable<ReviewScores> reviews,
  RankingMetric metric, {
  String? userId,
  bool worst = false,
  String Function(String)? bathroomIdentity,
}) {
  final result = <RankedBathroom>[];
  for (final b in bathrooms) {
    final matching = reviews
        .where(
          (r) =>
              (bathroomIdentity?.call(r.bathroomId) ?? r.bathroomId) == b.id &&
              (userId == null || r.authorId == userId),
        )
        .toList();
    if (matching.isNotEmpty) {
      result.add(
        RankedBathroom(
          b,
          matching.fold<double>(0, (sum, r) => sum + metric.score(r)) /
              matching.length,
          matching.length,
        ),
      );
    }
  }
  result.sort((a, b) {
    final order = worst
        ? a.score.compareTo(b.score)
        : b.score.compareTo(a.score);
    if (order != 0) return order;
    final name = a.bathroom.name.toLowerCase().compareTo(
      b.bathroom.name.toLowerCase(),
    );
    return name != 0 ? name : a.bathroom.id.compareTo(b.bathroom.id);
  });
  return result;
}
