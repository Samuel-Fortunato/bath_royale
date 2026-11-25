import 'bathroom_entry.dart';

enum BathroomSort { community, personal, name, latestVisit }

List<BathroomEntry> sortBathrooms(
  Iterable<BathroomEntry> entries,
  BathroomSort sort,
) {
  int descending<T extends Comparable<dynamic>>(T? a, T? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  final result = entries.toList();
  result.sort((a, b) {
    final primary = switch (sort) {
      BathroomSort.community => descending(
        a.communityRating,
        b.communityRating,
      ),
      BathroomSort.personal => descending(
        a.personalReview?.rating,
        b.personalReview?.rating,
      ),
      BathroomSort.latestVisit => descending(
        a.activity.lastVisitedAt,
        b.activity.lastVisitedAt,
      ),
      BathroomSort.name => 0,
    };
    if (primary != 0) return primary;
    final name = a.bathroom.name.toLowerCase().compareTo(
      b.bathroom.name.toLowerCase(),
    );
    return name != 0 ? name : a.bathroom.id.compareTo(b.bathroom.id);
  });
  return result;
}
