import 'bathroom.dart';
import 'bathroom_activity.dart';
import 'review.dart';
import 'visit.dart';
import 'tag_presentation.dart';
import 'community_review.dart';

/// Derived screen data; personal ratings never stand in for community averages.
class BathroomEntry {
  final Bathroom bathroom;
  final BathroomActivity activity;
  final Review? personalReview;
  final double? communityRating;
  final int reviewCount;
  final List<ReviewScores> communityScores;
  Iterable<ReviewTagData> get communityTags => communityScores.expand(
    (r) => r is CommunityReview
        ? r.tags
        : r is Review
        ? r.tags
        : <ReviewTagData>[],
  );
  double? mean(int Function(ReviewScores) score) => communityScores.isEmpty
      ? null
      : communityScores.fold<double>(0, (sum, r) => sum + score(r)) /
            communityScores.length;
  final String? catalogueLabel;

  BathroomEntry({
    required this.bathroom,
    required this.activity,
    required Iterable<Review> reviews,
    required Iterable<Visit> visits,
    Iterable<ReviewScores>? communityReviews,
    this.catalogueLabel,
  }) : communityScores = List.unmodifiable(communityReviews ?? reviews),
       personalReview = _latestPersonal(reviews, activity.userId, visits),
       reviewCount = (communityReviews ?? reviews).length,
       communityRating = (communityReviews ?? reviews).isEmpty
           ? null
           : (communityReviews ?? reviews).fold<double>(
                   0,
                   (sum, review) => sum + review.rating,
                 ) /
                 (communityReviews ?? reviews).length;

  static Review? _latestPersonal(
    Iterable<Review> reviews,
    String userId,
    Iterable<Visit> visits,
  ) {
    final chronology = {for (final v in visits) v.id: v.visitedAt};
    Review? latest;
    for (final review in reviews.where((r) => r.authorId == userId)) {
      final date = chronology[review.visitId]!;
      final previousDate = latest == null ? null : chronology[latest.visitId]!;
      if (latest == null ||
          date.isAfter(previousDate!) ||
          (date == previousDate &&
              review.visitId.compareTo(latest.visitId) > 0)) {
        latest = review;
      }
    }
    return latest;
  }
}
