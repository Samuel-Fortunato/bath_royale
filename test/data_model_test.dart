import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'package:bath_royale/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

const bathroom = Bathroom(id: 'wc', name: 'Test', createdBy: 'owner');
final date = DateTime.utc(2026);
Visit visit(String id, {String user = 'me', DateTime? at}) =>
    Visit(id: id, bathroomId: 'wc', userId: user, visitedAt: at ?? date);
Review review(
  String id,
  String visitId, {
  String user = 'me',
  DateTime? updatedAt,
  double rating = 4,
}) => Review(
  id: id,
  visitId: visitId,
  bathroomId: 'wc',
  authorId: user,
  createdAt: date,
  updatedAt: updatedAt,
  rating: rating,
  paperAvailability: 2,
  hygiene: 4,
  comfort: 4,
  aesthetics: 4,
);
AppState makeState({
  List<Visit> visits = const [],
  List<Review> reviews = const [],
}) => AppState(
  currentUserId: 'me',
  bathrooms: [bathroom],
  visits: visits,
  reviews: reviews,
);

void main() {
  test('optional repeat visits, derived latest and independent favourites', () {
    final app = makeState();
    addTearDown(app.dispose);
    app.toggleFavorite('wc');
    final first = app.recordVisit('wc', visitedAt: date);
    final next = app.recordVisit(
      'wc',
      visitedAt: date.add(const Duration(days: 1)),
    );
    expect(app.activityFor('wc').visitCount, 2);
    expect(app.activityFor('wc').lastVisitedAt, next.visitedAt);
    expect(app.reviews, isEmpty);
    expect(() => app.recordVisit('wc', visitedAt: date), throwsStateError);
    expect(app.undoVisit(first.id), isTrue);
    expect(app.activityFor('wc').lastVisitedAt, next.visitedAt);
    expect(app.activityFor('wc').isFavorite, isTrue);
    expect(app.undoVisit(next.id), isTrue);
    expect(app.activityFor('wc').lastVisitedAt, isNull);
  });
  test(
    'atomic creation, ownership, one review per visit and immutable link',
    () {
      final app = makeState();
      addTearDown(app.dispose);
      final v = visit('v');
      var notifications = 0;
      app.addListener(() => notifications++);
      expect(
        () => app.saveReview(review('r', 'v', user: 'other'), newVisit: v),
        throwsStateError,
      );
      expect(app.visits, isEmpty);
      app.saveReview(review('r', 'v'), newVisit: v);
      expect(notifications, 1);
      expect(app.activityFor('wc').visitCount, 1);
      expect(() => app.saveReview(review('other', 'v')), throwsStateError);
      expect(() => app.saveReview(review('r', 'missing')), throwsStateError);
      expect(app.undoVisit('v'), isFalse);
      expect(() => app.deleteVisit('v'), throwsStateError);
      expect(app.reviews.length, 1);
      app.saveReview(
        review(
          'r',
          'v',
          rating: 2,
          updatedAt: date.add(const Duration(days: 1)),
        ),
      );
      expect(app.visits.single.visitedAt, date);
      expect(app.reviews.single.rating, 2);
      app.deleteVisit('v', deleteReview: true);
      expect(app.visits, isEmpty);
      expect(app.reviews, isEmpty);
    },
  );
  test('constructor and mutations reject mismatched or foreign visits', () {
    final other = visit('other', user: 'other');
    expect(
      () => makeState(visits: [other], reviews: [review('r', 'other')]),
      throwsArgumentError,
    );
    expect(
      () => makeState(reviews: [review('r', 'missing')]),
      throwsArgumentError,
    );
    expect(
      () => makeState(visits: [visit('v'), visit('v2')]),
      throwsArgumentError,
    );
    final app = makeState(visits: [other]);
    addTearDown(app.dispose);
    expect(() => app.saveReview(review('r', 'other')), throwsStateError);
    expect(
      () => app.deleteVisit('other', deleteReview: true),
      throwsStateError,
    );
    expect(app.undoVisit('other'), isFalse);
    expect(() => app.visits.clear(), throwsUnsupportedError);
  });
  test(
    'reviewing an existing visit adds no duplicate and aggregates remain correct',
    () {
      final app = makeState(
        visits: [
          visit('v'),
          visit('theirs', user: 'other'),
        ],
        reviews: [review('theirs', 'theirs', user: 'other', rating: 2)],
      );
      addTearDown(app.dispose);
      app.saveReview(review('mine', 'v', rating: 4));
      expect(app.visits.length, 2);
      expect(app.entries.single.activity.visitCount, 1);
      expect(app.entries.single.communityRating, 3);
      expect(app.entries.single.personalReview!.rating, 4);
      expect(() => app.saveReview(review('duplicate', 'v')), throwsStateError);
      expect(app.reviews.length, 2);
    },
  );
  test('invalid ratings and backwards review updates are rejected', () {
    for (final score in [-1.0, 6.0, double.nan, double.infinity]) {
      expect(() => review('r', 'v', rating: score), throwsArgumentError);
    }
    final app = makeState(
      visits: [visit('v')],
      reviews: [review('r', 'v', updatedAt: date.add(const Duration(days: 1)))],
    );
    addTearDown(app.dispose);
    expect(() => app.saveReview(review('r', 'v')), throwsStateError);
  });
  test('sample reviews each link to exactly one visit', () {
    final app = AppState();
    addTearDown(app.dispose);
    expect(app.visits.length, 5);
    expect(app.reviews.length, 5);
    for (final r in app.reviews) {
      final v = app.visits.singleWhere((v) => v.id == r.visitId);
      expect(v.userId, r.authorId);
      expect(v.bathroomId, r.bathroomId);
    }
    expect(app.entries.last.activity.visitCount, 0);
  });
}
