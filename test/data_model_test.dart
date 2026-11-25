import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_activity.dart';
import 'package:bath_royale/models/bathroom_descriptions.dart';
import 'package:bath_royale/models/bathroom_filters.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

const facility = Bathroom(id: 'wc', name: 'Test', createdBy: 'other');
final day = DateTime.utc(2026, 1, 1);
Review review({
  String id = 'r',
  String author = 'me',
  String bathroom = 'wc',
  double rating = 4,
  int comfort = 4,
  int aesthetics = 4,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<String> tags = const [],
}) => Review(
  id: id,
  bathroomId: bathroom,
  authorId: author,
  createdAt: createdAt ?? day,
  updatedAt: updatedAt,
  rating: rating,
  paperAvailability: 2,
  hygiene: 4,
  comfort: comfort,
  aesthetics: aesthetics,
  tags: tags,
);
AppState state({
  List<Review> reviews = const [],
  List<BathroomActivity> activities = const [],
  String user = 'me',
}) => AppState(
  currentUserId: user,
  bathrooms: [facility],
  reviews: reviews,
  activities: activities,
);

void main() {
  test(
    'visit undo preserves favourites and refuses to replace a later visit',
    () {
      final app = state();
      addTearDown(app.dispose);
      app.recordVisit('wc', visitedAt: day);
      app.toggleFavorite('wc');
      expect(app.undoVisit('wc', recordedAt: day, previousAt: null), isTrue);
      expect(app.activityFor('wc').lastVisitedAt, isNull);
      expect(app.activityFor('wc').isFavorite, isTrue);
      app.recordVisit('wc', visitedAt: day);
      final later = day.add(const Duration(days: 1));
      app.recordVisit('wc', visitedAt: later);
      expect(app.undoVisit('wc', recordedAt: day, previousAt: null), isFalse);
      expect(app.activityFor('wc').lastVisitedAt, later);
      expect(app.undoVisit('wc', recordedAt: later, previousAt: day), isTrue);
      expect(app.activityFor('wc').lastVisitedAt, day);
    },
  );
  test(
    'multiple reviews, personal latest and community arithmetic mean are distinct',
    () {
      final app = state(
        reviews: [
          review(rating: 1),
          review(
            id: 'new',
            rating: 5,
            createdAt: day.add(const Duration(days: 1)),
          ),
          review(id: 'other', author: 'other', rating: 3),
        ],
      );
      addTearDown(app.dispose);
      var entry = app.entries.single;
      expect(entry.personalReview!.rating, 5);
      expect(entry.reviewCount, 3);
      expect(entry.communityRating, 3);
      app.saveReview(
        review(rating: 2, updatedAt: day.add(const Duration(days: 2))),
      );
      entry = app.entries.single;
      expect(entry.personalReview!.id, 'new');
      expect(entry.reviewCount, 3);
      expect(entry.communityRating, closeTo(10 / 3, 0.0001));
      final stranger = state(reviews: app.reviews, user: 'stranger');
      addTearDown(stranger.dispose);
      expect(stranger.entries.single.personalReview, isNull);
      expect(stranger.entries.single.communityRating, entry.communityRating);
    },
  );

  test(
    'empty ratings are absent and equal timestamps have deterministic order',
    () {
      final app = state();
      addTearDown(app.dispose);
      expect(app.entries.single.communityRating, isNull);
      expect(app.entries.single.reviewCount, 0);
      app.saveReview(review(id: 'b', rating: 0));
      app.saveReview(review(id: 'a'));
      expect(app.entries.single.personalReview!.id, 'b');
      expect(app.entries.single.communityRating, 2);
    },
  );

  test('review updates replace every field, copy tags and notify once', () {
    final app = state(reviews: [review()]);
    addTearDown(app.dispose);
    var notifications = 0;
    app.addListener(() => notifications++);
    final tags = ['clean'];
    final changed = Review(
      id: 'r',
      bathroomId: 'wc',
      authorId: 'me',
      createdAt: day,
      updatedAt: day.add(const Duration(hours: 1)),
      rating: 1.3,
      paperAvailability: 1,
      hygiene: 2,
      comfort: 0,
      aesthetics: 1,
      tags: tags,
    );
    app.saveReview(changed);
    tags.add('changed');
    final saved = app.entries.single.personalReview!;
    expect(saved, same(changed));
    expect(saved.tags, ['clean']);
    expect(() => saved.tags.add('no'), throwsUnsupportedError);
    expect(() => app.reviews.clear(), throwsUnsupportedError);
    expect(() => app.allBathrooms.clear(), throwsUnsupportedError);
    expect(notifications, 1);
    expect(app.activityFor('wc').lastVisitedAt, isNull);
    expect(app.activityFor('wc').isFavorite, isFalse);
  });

  test('ownership, identity, references and update chronology are guarded', () {
    final app = state(
      reviews: [
        review(),
        review(id: 'theirs', author: 'other'),
      ],
    );
    addTearDown(app.dispose);
    expect(() => app.saveReview(review(author: 'other')), throwsStateError);
    expect(() => app.saveReview(review(id: 'theirs')), throwsStateError);
    expect(
      () => app.saveReview(review(createdAt: day.add(const Duration(days: 1)))),
      throwsStateError,
    );
    expect(
      () => app.saveReview(review(bathroom: 'missing')),
      throwsArgumentError,
    );
    expect(() => app.toggleFavorite('missing'), throwsArgumentError);
    expect(
      () => app.recordVisit('missing', visitedAt: day),
      throwsArgumentError,
    );
    app.saveReview(review(updatedAt: day.add(const Duration(days: 2))));
    expect(() => app.saveReview(review()), throwsStateError);
    expect(app.reviews.length, 2);
    expect(() => state(reviews: [review(), review()]), throwsArgumentError);
    expect(
      () => state(reviews: [review(bathroom: 'missing')]),
      throwsArgumentError,
    );
  });

  test('invalid scores and timestamps are rejected at runtime', () {
    for (final score in [-1.0, 6.0, double.nan, double.infinity]) {
      expect(() => review(rating: score), throwsArgumentError);
    }
    expect(() => review(comfort: 5), throwsArgumentError);
    expect(() => review(aesthetics: -1), throwsArgumentError);
    expect(
      () => review(updatedAt: day.subtract(const Duration(days: 1))),
      throwsArgumentError,
    );
  });

  test(
    'favourites and explicit latest visits belong only to the current user',
    () {
      final otherActivity = BathroomActivity(
        userId: 'other',
        bathroomId: 'wc',
        isFavorite: true,
        lastVisitedAt: day,
      );
      final app = state(activities: [otherActivity]);
      addTearDown(app.dispose);
      var notifications = 0;
      app.addListener(() => notifications++);
      expect(app.activityFor('wc').isFavorite, isFalse);
      expect(app.activityFor('wc').lastVisitedAt, isNull);
      app.recordVisit('wc', visitedAt: day);
      app.toggleFavorite('wc');
      app.recordVisit('wc', visitedAt: day.subtract(const Duration(days: 1)));
      expect(notifications, 2);
      expect(app.activityFor('wc').lastVisitedAt, day);
      expect(app.entries.single.personalReview, isNull);
      expect(app.reviews, isEmpty);
      app.toggleFavorite('wc');
      expect(app.activityFor('wc').lastVisitedAt, day);
      expect(otherActivity.isFavorite, isTrue);
    },
  );

  test('sample state is independent and retains the five existing ratings', () {
    final first = AppState();
    final second = AppState();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.toggleFavorite('0');
    expect(second.activityFor('0').isFavorite, isFalse);
    expect(first.entries.map((b) => b.personalReview?.rating), [
      4.7,
      1.3,
      4.1,
      3,
      4.1,
      null,
    ]);
    expect(first.entries.first.personalReview!.hygieneText, '✨ Um brinco');
    expect(first.entries.first.personalReview!.comfortText, '🛋️ Poltrona');
    expect(first.entries.first.personalReview!.paperText, '🧻 Suficiente');
    expect(first.entries[2].personalReview!.aestheticText, '🌈 Scenic piss');
  });

  test('filters use personal reviews even with positive community ratings', () {
    final app = state(reviews: [review(author: 'other')]);
    addTearDown(app.dispose);
    final entry = app.entries.single;
    for (final filter in bathroomFilters) {
      expect(filter.test(entry), filter.id == BathroomFilterID.notReviewed);
    }
    app.saveReview(review(id: 'mine', rating: 1, comfort: 0, aesthetics: 0));
    final results = bathroomFilters
        .where((f) => f.test(app.entries.single))
        .map((f) => f.id);
    expect(results, [BathroomFilterID.reviewed, BathroomFilterID.badRating]);
  });
  test(
    'create and edit recompute filters without implying a visit or favourite',
    () {
      final app = state();
      addTearDown(app.dispose);
      app.saveReview(review(rating: 5));
      expect(
        bathroomFilters
            .firstWhere((f) => f.id == BathroomFilterID.goodRating)
            .test(app.entries.single),
        isTrue,
      );
      app.saveReview(
        review(rating: 1, updatedAt: day.add(const Duration(hours: 1))),
      );
      expect(
        bathroomFilters
            .firstWhere((f) => f.id == BathroomFilterID.goodRating)
            .test(app.entries.single),
        isFalse,
      );
      expect(
        bathroomFilters
            .firstWhere((f) => f.id == BathroomFilterID.badRating)
            .test(app.entries.single),
        isTrue,
      );
      expect(app.entries.single.reviewCount, 1);
      expect(app.entries.single.activity.lastVisitedAt, isNull);
      expect(app.entries.single.activity.isFavorite, isFalse);
    },
  );
}
