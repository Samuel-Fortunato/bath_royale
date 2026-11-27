import 'review.dart';
import 'tag_presentation.dart';

/// Public projection. It cannot contain a visit ID/date or an authentication ID.
class CommunityReview implements ReviewScores {
  final String id, username;
  @override
  final String bathroomId;
  @override
  final String authorId;
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
  CommunityReview.fromJson(Map<String, dynamic> p)
    : id = p['id'] as String,
      bathroomId = p['bathroom_id'] as String,
      authorId = p['author_id'] as String,
      username = p['username'] as String,
      rating = (p['rating'] as num).toDouble(),
      paperAvailability = p['paper'] as int,
      hygiene = p['hygiene'] as int,
      comfort = p['comfort'] as int,
      aesthetics = p['aesthetics'] as int,
      tags = List.unmodifiable(
        (p['tags'] as List).map(
          (t) => ReviewTagData.fromJson(Map<String, dynamic>.from(t as Map)),
        ),
      ),
      comment = p['comment'] as String?;
}
