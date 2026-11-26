import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_activity.dart';
import 'package:bath_royale/models/bathroom_entry.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/models/visit.dart';
import 'sample_data.dart';
import 'package:uuid/uuid.dart';
import '../storage/local_store.dart';
import '../storage/bathroom_repository.dart';

class AppState extends ChangeNotifier {
  final String currentUserId;
  final BathroomRepository? repository;
  void Function()? _pendingWrite;
  void Function()? _pendingApply;
  Object? storageError;
  Completer<void>? _pendingCompletion;

  /// UI success continuations wait here if the local transaction needs retry.
  Future<void> get persistenceComplete =>
      _pendingCompletion?.future ?? Future.value();
  final _visitInteraction = Stopwatch();
  Visit? _lastRegistered;
  static String newEntityId() => const Uuid().v4();

  LocalData get localData => LocalData(
    bathrooms: allBathrooms,
    visits: visits,
    reviews: reviews,
    favourites: _activities.values.toList(),
    darkMode: darkMode,
  );

  static AppState restore(LocalStore store) {
    final repository = BathroomRepository(store);
    final data = repository.load();
    final state = data == null
        ? AppState(
            repository: repository,
            visits: [
              for (final r in createSampleReviews())
                Visit(
                  id: r.visitId,
                  bathroomId: r.bathroomId,
                  userId: r.authorId,
                  visitedAt: r.createdAt,
                ),
              Visit(
                id: 'sample-unreviewed',
                bathroomId: '0',
                userId: localUserId,
                visitedAt: DateTime.utc(2026, 1, 2),
              ),
            ],
            activities: [
              const BathroomActivity(
                userId: localUserId,
                bathroomId: '3',
                isFavorite: true,
              ),
            ],
          )
        : AppState(
            repository: repository,
            bathrooms: data.bathrooms,
            visits: data.visits,
            reviews: data.reviews,
            activities: data.favourites,
            darkMode: data.darkMode,
          );
    try {
      if (data == null) repository.initialize(state.localData);
    } catch (_) {
      state.dispose();
      rethrow;
    }
    return state;
  }

  // A single failed action retains its exact payload/IDs until explicit retry.
  // Observable domain state always represents committed data.
  void _mutate(void Function() write, void Function() apply) {
    if (_pendingWrite != null) {
      throw StateError('Retry pending storage action first');
    }
    _pendingCompletion = Completer<void>();
    _pendingWrite = write;
    _pendingApply = apply;
    retryStorage();
  }

  void retryStorage() {
    final write = _pendingWrite;
    if (write == null) return;
    try {
      write();
    } catch (error) {
      storageError = error;
      notifyListeners(); // Error notification only; no successful mutation.
      return;
    }
    final apply = _pendingApply!;
    _pendingWrite = null;
    _pendingApply = null;
    storageError = null;
    apply();
    _pendingCompletion!.complete();
    _pendingCompletion = null;
    notifyListeners();
  }

  final List<Bathroom> _bathrooms;

  List<Bathroom> get allBathrooms => List.unmodifiable(_bathrooms);
  final List<Review> _reviews;
  final List<Visit> _visits;
  final Map<(String, String), BathroomActivity> _activities = {};

  AppState({
    this.currentUserId = localUserId,
    this.repository,
    this.darkMode = true,
    List<Bathroom>? bathrooms,
    List<Review>? reviews,
    List<Visit>? visits,
    List<BathroomActivity>? activities,
  }) : _bathrooms = List.of(bathrooms ?? sampleBathrooms),
       _reviews = List.of(
         reviews ?? (bathrooms == null ? createSampleReviews() : <Review>[]),
       ),
       _visits = List.of(
         visits ??
             (bathrooms == null && reviews == null
                 ? [
                     for (final r in createSampleReviews())
                       Visit(
                         id: r.visitId,
                         bathroomId: r.bathroomId,
                         userId: r.authorId,
                         visitedAt: r.createdAt,
                       ),
                   ]
                 : <Visit>[]),
       ) {
    if (currentUserId.isEmpty ||
        allBathrooms.any((b) => b.id.isEmpty || b.createdBy.isEmpty) ||
        allBathrooms.map((b) => b.id).toSet().length != allBathrooms.length ||
        _reviews.map((r) => r.id).toSet().length != _reviews.length) {
      throw ArgumentError('Invalid or duplicate identifiers');
    }
    if (_visits.map((v) => v.id).toSet().length != _visits.length) {
      throw ArgumentError('Duplicate visit identifiers');
    }
    for (final visit in _visits) {
      _requireBathroom(visit.bathroomId);
    }
    if (_visits
            .map((v) => (v.userId, v.bathroomId, v.visitedAt))
            .toSet()
            .length !=
        _visits.length) {
      throw ArgumentError('Duplicate visits');
    }
    final linked = <String>{};
    for (final review in _reviews) {
      _requireBathroom(review.bathroomId);
      final matches = _visits.where((v) => v.id == review.visitId);
      if (matches.length != 1 ||
          matches.single.bathroomId != review.bathroomId ||
          matches.single.userId != review.authorId ||
          !linked.add(review.visitId)) {
        throw ArgumentError('Invalid review visit');
      }
    }
    final initialActivities = activities ?? <BathroomActivity>[];
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

  Bathroom createBathroom(String name, {String? emoji, int? accent}) {
    if (emoji != null && !Bathroom.emojis.contains(emoji)) {
      throw ArgumentError('Invalid emoji');
    }
    if (accent != null &&
        (accent < 0 || accent >= Bathroom.accentNames.length)) {
      throw ArgumentError('Invalid accent');
    }
    final error = validateBathroomName(name);
    if (error != null) throw ArgumentError(error);
    final bathroom = Bathroom(
      id: newEntityId(),
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
      createdBy: currentUserId,
      emoji: emoji,
      accent: accent,
    );
    _mutate(
      () => repository?.createBathroom(bathroom),
      () => _bathrooms.add(bathroom),
    );
    return bathroom;
  }

  void updateBathroom(Bathroom bathroom) {
    final index = _bathrooms.indexWhere((b) => b.id == bathroom.id);
    if (index < 0 || _bathrooms[index].createdBy != bathroom.createdBy) {
      throw StateError('Bathroom identity is immutable');
    }
    final error = validateBathroomName(bathroom.name);
    if (normalizeName(_bathrooms[index].name) != normalizeName(bathroom.name) &&
        error != null) {
      throw ArgumentError(error);
    }
    if (!Bathroom.emojis.contains(bathroom.emoji) ||
        bathroom.accent < 0 ||
        bathroom.accent >= Bathroom.accentNames.length) {
      throw ArgumentError('Invalid identity');
    }
    _mutate(
      () => repository?.updateBathroom(bathroom),
      () => _bathrooms[index] = bathroom,
    );
  }

  List<Review> get reviews => List.unmodifiable(_reviews);
  List<Visit> get visits => List.unmodifiable(_visits);

  List<Visit> visitsFor(String bathroomId) {
    _requireBathroom(bathroomId);
    return _visits
        .where((v) => v.bathroomId == bathroomId && v.userId == currentUserId)
        .toList()
      ..sort((a, b) {
        final order = b.visitedAt.compareTo(a.visitedAt);
        return order == 0 ? b.id.compareTo(a.id) : order;
      });
  }

  Review? reviewForVisit(String visitId) {
    for (final review in _reviews) {
      if (review.visitId == visitId) return review;
    }
    return null;
  }

  List<BathroomEntry> get entries => [
    for (final bathroom in allBathrooms)
      BathroomEntry(
        bathroom: bathroom,
        activity: activityFor(bathroom.id),
        reviews: _reviews.where((r) => r.bathroomId == bathroom.id).toList(),
        visits: _visits,
      ),
  ];

  BathroomActivity activityFor(String bathroomId) {
    _requireBathroom(bathroomId);
    final visits = visitsFor(bathroomId);
    return BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: _activities[(currentUserId, bathroomId)]?.isFavorite ?? false,
      lastVisitedAt: visits.isEmpty ? null : visits.first.visitedAt,
      visitCount: visits.length,
    );
  }

  void _requireBathroom(String id) {
    if (!allBathrooms.any((bathroom) => bathroom.id == id)) {
      throw ArgumentError.value(id, 'bathroomId', 'Unknown bathroom');
    }
  }

  void toggleFavorite(String bathroomId) {
    final previous = activityFor(bathroomId);
    final activity = BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: !previous.isFavorite,
    );
    _mutate(
      () => repository?.setFavourite(
        currentUserId,
        bathroomId,
        activity.isFavorite,
      ),
      () => _activities[(currentUserId, bathroomId)] = activity,
    );
  }

  String newVisitId() => newEntityId();

  void _validateNewVisit(Visit visit) {
    _requireBathroom(visit.bathroomId);
    if (visit.userId != currentUserId ||
        _visits.any(
          (v) =>
              v.id == visit.id ||
              (v.userId == visit.userId &&
                  v.bathroomId == visit.bathroomId &&
                  v.visitedAt == visit.visitedAt),
        )) {
      throw StateError('Invalid or duplicate visit');
    }
  }

  Visit recordVisit(String bathroomId, {required DateTime visitedAt}) {
    final previous = _lastRegistered;
    if (previous != null &&
        previous.bathroomId == bathroomId &&
        _visitInteraction.elapsedMilliseconds < 800 &&
        visitedAt.difference(previous.visitedAt).inMilliseconds.abs() < 800 &&
        _visits.contains(previous)) {
      return previous;
    }
    final visit = Visit(
      id: newVisitId(),
      bathroomId: bathroomId,
      userId: currentUserId,
      visitedAt: visitedAt,
    );
    _validateNewVisit(visit);
    _mutate(() => repository?.recordVisit(visit), () {
      _visits.add(visit);
      _lastRegistered = visit;
      _visitInteraction.reset();
      _visitInteraction.start();
    });
    return visit;
  }

  /// Undo only the exact newly created visit, never an associated review.
  bool undoVisit(String visitId) {
    final matches = _visits.where(
      (v) => v.id == visitId && v.userId == currentUserId,
    );
    if (matches.isEmpty || reviewForVisit(visitId) != null) return false;
    final visit = matches.single;
    _mutate(
      () => repository?.deleteVisit(visitId),
      () => _visits.remove(visit),
    );
    return storageError == null;
  }

  void deleteVisit(String visitId, {bool deleteReview = false}) {
    final matches = _visits.where(
      (v) => v.id == visitId && v.userId == currentUserId,
    );
    if (matches.isEmpty) throw StateError('Visit not found');
    final review = reviewForVisit(visitId);
    if (review != null && !deleteReview) throw StateError('Visit has a review');
    final visit = matches.single;
    _mutate(() => repository?.deleteVisit(visitId), () {
      if (review != null) _reviews.remove(review);
      _visits.remove(visit);
    });
  }

  /// Local ownership guard, not authentication or a future security boundary.
  void saveReview(Review review, {Visit? newVisit}) {
    _requireBathroom(review.bathroomId);
    if (review.authorId != currentUserId) {
      throw StateError('Only the current author can save a review');
    }
    final index = _reviews.indexWhere((r) => r.id == review.id);
    if (newVisit != null) {
      if (index >= 0 || newVisit.id != review.visitId) {
        throw StateError('Invalid new visit');
      }
      _validateNewVisit(newVisit);
    }
    final candidates = newVisit == null
        ? _visits.where((v) => v.id == review.visitId).toList()
        : [newVisit];
    if (candidates.length != 1 ||
        candidates.single.userId != review.authorId ||
        candidates.single.bathroomId != review.bathroomId ||
        _reviews.any((r) => r.visitId == review.visitId && r.id != review.id)) {
      throw StateError('Invalid review visit');
    }
    if (index >= 0) {
      final previous = _reviews[index];
      if (previous.authorId != currentUserId ||
          previous.bathroomId != review.bathroomId ||
          previous.visitId != review.visitId ||
          previous.createdAt != review.createdAt ||
          review.updatedAt.isBefore(previous.updatedAt)) {
        throw StateError(
          'Review identity is immutable; updates must not go backwards',
        );
      }
    }
    _mutate(
      () =>
          repository?.saveReview(review, newVisit: newVisit, isNew: index < 0),
      () {
        if (index < 0) {
          if (newVisit != null) _visits.add(newVisit);
          _reviews.add(review);
        } else {
          _reviews[index] = review;
        }
      },
    );
  }

  bool darkMode;
  void toggleTheme() {
    final value = !darkMode;
    _mutate(() => repository?.setDarkMode(value), () => darkMode = value);
  }
}
