/// An individual, author-owned review. Repeat reviews are separate records.
class Review {
  final String id;
  final String visitId;
  final String bathroomId;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double rating;
  final int paperAvailability;
  final int hygiene;
  final int comfort;
  final int aesthetics;
  final List<String> tags;

  Review({
    required this.id,
    required this.visitId,
    required this.bathroomId,
    required this.authorId,
    required this.createdAt,
    DateTime? updatedAt,
    required this.rating,
    required this.paperAvailability,
    required this.hygiene,
    required this.comfort,
    required this.aesthetics,
    List<String> tags = const [],
  }) : updatedAt = updatedAt ?? createdAt,
       tags = List.unmodifiable(tags) {
    if (id.isEmpty ||
        visitId.isEmpty ||
        bathroomId.isEmpty ||
        authorId.isEmpty) {
      throw ArgumentError('Review identifiers must not be empty');
    }
    if (!rating.isFinite ||
        rating < 0 ||
        rating > 5 ||
        paperAvailability < 0 ||
        paperAvailability > 2 ||
        hygiene < 0 ||
        hygiene > 4 ||
        comfort < 0 ||
        comfort > 4 ||
        aesthetics < 0 ||
        aesthetics > 4) {
      throw ArgumentError('Invalid review rating');
    }
    if (this.updatedAt.isBefore(createdAt)) {
      throw ArgumentError('Review update precedes creation');
    }
  }
}
