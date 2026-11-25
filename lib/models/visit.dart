/// One real experience at a bathroom. Reviews are optional.
class Visit {
  final String id;
  final String bathroomId;
  final String userId;
  final DateTime visitedAt;

  Visit({
    required this.id,
    required this.bathroomId,
    required this.userId,
    required this.visitedAt,
  }) {
    if (id.isEmpty || bathroomId.isEmpty || userId.isEmpty) {
      throw ArgumentError('Visit identifiers must not be empty');
    }
  }
}
