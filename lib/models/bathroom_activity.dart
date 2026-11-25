/// Personal favourite and visit summary derived for one user and facility.
class BathroomActivity {
  final String userId;
  final String bathroomId;
  final bool isFavorite;
  final DateTime? lastVisitedAt;
  final int visitCount;

  const BathroomActivity({
    required this.userId,
    required this.bathroomId,
    this.isFavorite = false,
    this.lastVisitedAt,
    this.visitCount = 0,
  });
}
