import 'package:characters/characters.dart';
import 'tag_presentation.dart';

/// Shared scoring contract; public reviews remain separate from personal visits.
abstract interface class ReviewScores {
  String get bathroomId;
  String get authorId;
  double get rating;
  int get paperAvailability;
  int get hygiene;
  int get comfort;
  int get aesthetics;
}

/// An individual, author-owned review. Repeat reviews are separate records.
class Review implements ReviewScores {
  final String id;
  final String visitId;
  @override
  final String bathroomId;
  @override
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  @override
  final double rating;
  @override
  final int paperAvailability;
  @override
  final int hygiene;
  @override
  final int comfort;
  @override
  final int aesthetics;
  final List<ReviewTagData> tags;
  final String? comment;

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
    Iterable<Object> tags = const [],
    String? comment,
  }) : updatedAt = updatedAt ?? createdAt,
       comment = comment == null || comment.trim().isEmpty
           ? null
           : comment.trim(),
       tags = List.unmodifiable(
         tags.map(
           (tag) =>
               tag is ReviewTagData ? tag : ReviewTagData.legacy(tag as String),
         ),
       ) {
    if (this.comment != null && this.comment!.characters.length > 500) {
      throw ArgumentError('Comment exceeds 500 characters');
    }
    if (this.tags.length > 10 ||
        this.tags.map(TagPresentation.key).toSet().length != this.tags.length) {
      throw ArgumentError('Invalid or duplicate tags');
    }
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
