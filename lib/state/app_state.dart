import 'package:flutter/foundation.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_activity.dart';
import 'package:bath_royale/models/bathroom_entry.dart';
import 'package:bath_royale/models/review.dart';
import 'sample_data.dart';

class AppState extends ChangeNotifier {
  final String currentUserId;
  final List<Bathroom> _bathrooms;

  List<Bathroom> get allBathrooms => List.unmodifiable(_bathrooms);
  final List<Review> _reviews;
  final Map<(String, String), BathroomActivity> _activities = {};

  AppState({
    this.currentUserId = localUserId,
    List<Bathroom>? bathrooms,
    List<Review>? reviews,
    List<BathroomActivity>? activities,
  }) : _bathrooms = List.of(bathrooms ?? sampleBathrooms),
       _reviews = List.of(
         reviews ?? (bathrooms == null ? createSampleReviews() : <Review>[]),
       ) {
    if (currentUserId.isEmpty ||
        allBathrooms.any((b) => b.id.isEmpty || b.createdBy.isEmpty) ||
        allBathrooms.map((b) => b.id).toSet().length != allBathrooms.length ||
        _reviews.map((r) => r.id).toSet().length != _reviews.length) {
      throw ArgumentError('Invalid or duplicate identifiers');
    }
    for (final review in _reviews) {
      _requireBathroom(review.bathroomId);
    }
    // The original five sample experiences are explicitly seeded as visits.
    final initialActivities =
        activities ??
        (bathrooms == null
            ? [
                for (final review in createSampleReviews())
                  BathroomActivity(
                    userId: localUserId,
                    bathroomId: review.bathroomId,
                    lastVisitedAt: review.createdAt,
                  ),
              ]
            : <BathroomActivity>[]);
    for (final activity in initialActivities) {
      _requireBathroom(activity.bathroomId);
      final key = (activity.userId, activity.bathroomId);
      if (activity.userId.isEmpty || _activities.containsKey(key)) {
        throw ArgumentError('Invalid or duplicate personal activity');
      }
      _activities[key] = activity;
    }
  }

  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String? validateBathroomName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'Dá um nome a este trono.';
    if (cleaned.length > 100) return 'Usa até 100 caracteres.';
    if (cleaned.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      return 'Usa apenas texto numa linha.';
    }
    if (_bathrooms.any((b) => normalizeName(b.name) == normalizeName(name))) {
      return 'Já existe uma casa de banho com este nome.';
    }
    return null;
  }

  Bathroom createBathroom(String name) {
    final error = validateBathroomName(name);
    if (error != null) throw ArgumentError(error);
    var serial = _bathrooms.length + 1;
    while (_bathrooms.any((b) => b.id == 'bathroom-$serial')) {
      serial++;
    }
    final bathroom = Bathroom(
      id: 'bathroom-$serial',
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
      createdBy: currentUserId,
    );
    _bathrooms.add(bathroom);
    notifyListeners();
    return bathroom;
  }

  List<Review> get reviews => List.unmodifiable(_reviews);

  List<BathroomEntry> get entries => [
    for (final bathroom in allBathrooms)
      BathroomEntry(
        bathroom: bathroom,
        activity: activityFor(bathroom.id),
        reviews: _reviews.where((r) => r.bathroomId == bathroom.id).toList(),
      ),
  ];

  BathroomActivity activityFor(String bathroomId) {
    _requireBathroom(bathroomId);
    return _activities[(currentUserId, bathroomId)] ??
        BathroomActivity(userId: currentUserId, bathroomId: bathroomId);
  }

  void _requireBathroom(String id) {
    if (!allBathrooms.any((bathroom) => bathroom.id == id)) {
      throw ArgumentError.value(id, 'bathroomId', 'Unknown bathroom');
    }
  }

  void toggleFavorite(String bathroomId) {
    final previous = activityFor(bathroomId);
    _activities[(currentUserId, bathroomId)] = BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: !previous.isFavorite,
      lastVisitedAt: previous.lastVisitedAt,
    );
    notifyListeners();
  }

  /// Records the latest known visit; repeated/older dates do not invent counts.
  void recordVisit(String bathroomId, {required DateTime visitedAt}) {
    final previous = activityFor(bathroomId);
    if (previous.lastVisitedAt != null &&
        !visitedAt.isAfter(previous.lastVisitedAt!)) {
      return;
    }
    _activities[(currentUserId, bathroomId)] = BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: previous.isFavorite,
      lastVisitedAt: visitedAt,
    );
    notifyListeners();
  }

  /// Local ownership guard, not authentication or a future security boundary.
  void saveReview(Review review) {
    _requireBathroom(review.bathroomId);
    if (review.authorId != currentUserId) {
      throw StateError('Only the current author can save a review');
    }
    final index = _reviews.indexWhere((r) => r.id == review.id);
    if (index < 0) {
      _reviews.add(review);
    } else {
      final previous = _reviews[index];
      if (previous.authorId != currentUserId ||
          previous.bathroomId != review.bathroomId ||
          previous.createdAt != review.createdAt ||
          review.updatedAt.isBefore(previous.updatedAt)) {
        throw StateError(
          'Review identity is immutable; updates must not go backwards',
        );
      }
      _reviews[index] = review;
    }
    notifyListeners();
  }

  bool darkMode = true;
  void toggleTheme() {
    darkMode = !darkMode;
    notifyListeners();
  }
}
