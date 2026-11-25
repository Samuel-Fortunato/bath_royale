import 'bathroom.dart';
import 'bathroom_activity.dart';
import 'review.dart';
import 'visit.dart';

/// Derived screen data; personal ratings never stand in for community averages.
class BathroomEntry {
  final Bathroom bathroom;
  final BathroomActivity activity;
  final Review? personalReview;
  final double? communityRating;
  final int reviewCount;

  BathroomEntry({
    required this.bathroom,
    required this.activity,
    required Iterable<Review> reviews,
    required Iterable<Visit> visits,
  }) : personalReview = _latestPersonal(reviews, activity.userId, visits),
       reviewCount = reviews.length,
       communityRating = reviews.isEmpty
           ? null
           : reviews.fold<double>(0, (sum, review) => sum + review.rating) /
                 reviews.length;

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
