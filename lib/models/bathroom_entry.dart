import 'bathroom.dart';
import 'bathroom_activity.dart';
import 'review.dart';

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
  }) : personalReview = _latestPersonal(reviews, activity.userId),
       reviewCount = reviews.length,
       communityRating = reviews.isEmpty
           ? null
           : reviews.fold<double>(0, (sum, review) => sum + review.rating) /
                 reviews.length;

  static Review? _latestPersonal(Iterable<Review> reviews, String userId) {
    Review? latest;
    for (final review in reviews.where((r) => r.authorId == userId)) {
      // Creation time chooses the latest experience; editing an older one
      // does not promote it. IDs break timestamp ties deterministically.
      if (latest == null ||
          review.createdAt.isAfter(latest.createdAt) ||
          (review.createdAt == latest.createdAt &&
              review.id.compareTo(latest.id) > 0)) {
        latest = review;
      }
    }
    return latest;
  }
}
