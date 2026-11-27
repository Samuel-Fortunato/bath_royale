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
  final scores = <String, (double, int)>{};
  for (final r in reviews) {
    if (userId != null && r.authorId != userId) continue;
    final id = bathroomIdentity?.call(r.bathroomId) ?? r.bathroomId;
    final previous = scores[id] ?? (0.0, 0);
    scores[id] = (previous.$1 + metric.score(r), previous.$2 + 1);
  }
  for (final b in bathrooms) {
    final score = scores[b.id];
    if (score != null) {
      result.add(RankedBathroom(b, score.$1 / score.$2, score.$2));
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
