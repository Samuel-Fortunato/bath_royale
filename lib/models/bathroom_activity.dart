/// Private state for one user and facility. A visit is explicit, not a review.
class BathroomActivity {
  final String userId;
  final String bathroomId;
  final bool isFavorite;
  final DateTime? lastVisitedAt;

  const BathroomActivity({
    required this.userId,
    required this.bathroomId,
    this.isFavorite = false,
    this.lastVisitedAt,
  });
}
