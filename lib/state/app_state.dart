import 'dart:async';
import 'dart:convert';
import '../sync/community_catalogue.dart';
import '../sync/sync_store.dart';
import '../models/community_review.dart';
import '../models/provenance.dart';
import 'package:characters/characters.dart';
import '../sync/private_sync_controller.dart';
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
  PrivateSyncController? synchronization;
  CommunityCatalogue? community;
  bool readOnly = false;
  bool get communityEnabled => community != null;
  bool get canContribute => communityEnabled && !readOnly;
  bool isShared(String id) =>
      community?.bathrooms.any((b) => b.id == id) == true ||
      repository?.store.database.select(
            'SELECT id FROM catalogue_bathrooms WHERE id=?',
            [id],
          ).isNotEmpty ==
          true;
  bool isAvailable(String id) =>
      !isShared(id) || community?.bathrooms.any((b) => b.id == id) == true;
  Map<String, String> get bathroomLinks => {
    if (repository != null)
      for (final r in repository!.store.database.select(
        'SELECT * FROM bathroom_links',
      ))
        r['private_id'] as String: r['shared_id'] as String,
  };
  String sharedIdentity(String id) => bathroomLinks[id] ?? id;
  List<CommunityReview> communityReviewsFor(String id) =>
      community?.reviews
          .where((r) => r.bathroomId == sharedIdentity(id))
          .toList() ??
      [];
  String? get publicUsername =>
      _effective('profile', currentUserId)?['username'] as String?;
  Map<String, dynamic>? _effective(String kind, String id) {
    final db = repository?.store.database;
    if (db == null) return null;
    final pending = db.select(
      "SELECT payload,state,acknowledged_revision FROM outbox WHERE entity_type=? AND entity_id=? AND operation_id NOT IN (SELECT operation_id FROM sync_resolutions) ORDER BY sequence DESC LIMIT 1",
      [kind, id],
    );
    final remote = db.select(
      'SELECT payload,revision FROM remote_records WHERE entity_type=? AND entity_id=?',
      [kind, id],
    );
    if (pending.isNotEmpty) {
      final row = pending.single;
      if (row['state'] != 'acknowledged' ||
          remote.isEmpty ||
          (row['acknowledged_revision'] as int) >
              (remote.single['revision'] as int)) {
        return Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String) as Map,
        );
      }
    }
    return remote.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(remote.single['payload'] as String) as Map,
          );
  }

  bool isPublished(String reviewId) =>
      _effective('publication', reviewId)?['published'] == true;
  void attachCommunity(CommunityCatalogue catalogue, {bool anonymous = false}) {
    community = catalogue;
    readOnly = anonymous;
    community!.addListener(_catalogueChanged);
    _catalogueChanged();
  }

  void _catalogueChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void materializeCatalogue() {
    final store = repository?.store;
    if (store == null || community == null) return;
    store.transaction(() {
      for (final b in community!.bathrooms) {
        if (store.database.select('SELECT id FROM bathrooms WHERE id=?', [
          b.id,
        ]).isEmpty) {
          store.insertBathroom(b, provenance: Provenance.remote);
        }
        if (store.database.select(
          "SELECT id FROM bathrooms WHERE id=? AND creator='catalogue'",
          [b.id],
        ).isNotEmpty) {
          store.database.execute(
            'INSERT OR IGNORE INTO catalogue_bathrooms VALUES(?)',
            [b.id],
          );
        }
      }
    });
    final retained = store.load()!.bathrooms;
    _bathrooms.addAll(
      retained.where((b) => !_bathrooms.any((p) => p.id == b.id)),
    );
  }

  void _writable() {
    if (readOnly) throw StateError('Authentication required');
  }

  void _communityCommand(
    String kind,
    String id,
    String command,
    Map<String, Object?> payload, {
    List<(String, String)> references = const [],
  }) {
    _writable();
    if (!canContribute) throw StateError('Community account required');
    final store = repository!.store;
    _mutate(
      () => store.transaction(
        () => SyncStore(
          store,
        ).enqueue(kind, id, command, payload, references: references),
      ),
      () {},
    );
  }

  void setPublicUsername(String username) {
    final clean = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9_]{2,29}$').hasMatch(clean)) {
      throw ArgumentError('Invalid public username');
    }
    _communityCommand('profile', currentUserId, 'setUsername', {
      'username': clean,
    });
  }

  void associateBathroom(String privateId, String sharedId) {
    _writable();
    materializeCatalogue();
    final store = repository!.store;
    final b = allBathrooms.singleWhere((b) => b.id == privateId);
    if (!canContribute ||
        isShared(privateId) ||
        b.createdBy != currentUserId ||
        bathroomLinks.containsKey(privateId) ||
        !isShared(sharedId) ||
        !isAvailable(sharedId) ||
        ![
          Provenance.userCreated,
          Provenance.remote,
        ].contains(store.bathroomProvenance(privateId))) {
      throw StateError('Ineligible association');
    }
    _mutate(
      () => store.transaction(() {
        SyncStore(store).enqueue(
          'link',
          privateId,
          'linkBathroom',
          {'shared_id': sharedId},
          references: [('bathroom', privateId)],
        );
        store.database.execute('INSERT INTO bathroom_links VALUES(?,?)', [
          privateId,
          sharedId,
        ]);
      }),
      () {},
    );
  }

  void publishReview(Review review, {required bool publish}) {
    if (review.authorId != currentUserId ||
        (publish &&
            (publicUsername == null ||
                !isShared(sharedIdentity(review.bathroomId)) ||
                !isAvailable(sharedIdentity(review.bathroomId))))) {
      throw StateError('Ineligible publication');
    }
    _communityCommand(
      'publication',
      review.id,
      publish ? 'publishReview' : 'withdrawReview',
      {'review_id': review.id, 'published': publish},
      references: [
        ('review', review.id),
        ('link', review.bathroomId),
        ('profile', currentUserId),
      ],
    );
  }

  void reportContent(String kind, String id, String reason) {
    final text = reason.trim();
    if (text.isEmpty || text.characters.length > 500) {
      throw ArgumentError('Invalid report');
    }
    _communityCommand('report', newEntityId(), 'reportContent', {
      'kind': kind,
      'target': id,
      'reason': text,
    });
  }

  void Function()? _pendingWrite;
  void Function()? _pendingApply;
  Object? storageError;
  Completer<void>? _pendingCompletion;

  bool _disposed = false;
  int _openDrafts = 0;
  bool get hasUncommittedWork => _openDrafts > 0 || _pendingWrite != null;

  /// Conservatively retain any open editor, including pristine forms.
  /// The returned release callback is idempotent and belongs to that editor.
  VoidCallback retainDraft() {
    _requireAlive();
    _openDrafts++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _openDrafts--;
      synchronization?.request();
    };
  }

  void _requireAlive() {
    if (_disposed) throw StateError('Application state is disposed');
  }

  @override
  void dispose() {
    community?.removeListener(_catalogueChanged);
    synchronization?.dispose();
    _disposed = true;
    super.dispose();
  }

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
    if (store.namespace.kind != 'guest') {
      throw ArgumentError('Application bootstrap is guest-only');
    }
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

  /// Restore isolated account records without guest samples or implicit transfer.
  static AppState restoreAccountForTesting(BathroomRepository repository) {
    if (!repository.store.namespace.isAccount) {
      throw ArgumentError('Account store required');
    }
    final data = repository.load();
    final state = AppState(
      currentUserId: repository.store.namespace.subject,
      repository: repository,
      bathrooms: data?.bathrooms ?? [],
      visits: data?.visits ?? [],
      reviews: data?.reviews ?? [],
      activities: data?.favourites ?? [],
      darkMode: data?.darkMode ?? true,
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
    _requireAlive();
    _writable();
    if (_pendingWrite != null) {
      throw StateError('Retry pending storage action first');
    }
    _pendingCompletion = Completer<void>();
    _pendingWrite = write;
    _pendingApply = apply;
    retryStorage();
  }

  void retryStorage() {
    _requireAlive();
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

  List<Bathroom> get allBathrooms => List.unmodifiable([
    ..._bathrooms,
    if (community != null)
      ...community!.bathrooms.where(
        (b) => !_bathrooms.any((p) => p.id == b.id),
      ),
  ]);
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
    if (repository?.store.namespace.isAccount == true &&
        (currentUserId != repository!.store.namespace.subject ||
            bathrooms == null ||
            reviews == null ||
            visits == null ||
            activities == null)) {
      throw ArgumentError('Account state requires explicit data and subject');
    }
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

  /// A remote projection is applied only outside editors and failed commits.
  bool reloadAccountData() {
    if (_disposed || hasUncommittedWork) return false;
    final data = repository!.load()!;
    _bathrooms
      ..clear()
      ..addAll(data.bathrooms);
    _visits
      ..clear()
      ..addAll(data.visits);
    _reviews
      ..clear()
      ..addAll(data.reviews);
    _activities.clear();
    for (final f in data.favourites) {
      _activities[(f.userId, f.bathroomId)] = f;
    }
    _lastRegistered = null;
    notifyListeners();
    return true;
  }

  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String? validateBathroomName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'Dá um nome a este trono.';
    if (cleaned.characters.length > 100) return 'Usa até 100 caracteres.';
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
    _writable();
    final error = validateBathroomName(name);
    if (error != null) throw ArgumentError(error);
    final bathroom = Bathroom(
      id: newEntityId(),
      name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
      createdBy: canContribute ? 'catalogue' : currentUserId,
      emoji: emoji,
      accent: accent,
    );
    _mutate(() {
      if (canContribute) {
        final store = repository!.store;
        store.transaction(() {
          store.insertBathroom(bathroom, provenance: Provenance.remote);
          store.database.execute('INSERT INTO catalogue_bathrooms VALUES(?)', [
            bathroom.id,
          ]);
          SyncStore(
            store,
          ).enqueue('contribution', bathroom.id, 'contributeBathroom', {
            'name': bathroom.name,
            'emoji': bathroom.emoji,
            'accent': bathroom.accent,
          });
        });
      } else {
        repository?.createBathroom(bathroom);
      }
    }, () => _bathrooms.add(bathroom));
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
    final ids = {
      bathroomId,
      ...bathroomLinks.entries
          .where((e) => e.value == bathroomId)
          .map((e) => e.key),
    };
    return _visits
        .where((v) => ids.contains(v.bathroomId) && v.userId == currentUserId)
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
    for (final bathroom in allBathrooms.where(
      (b) => !bathroomLinks.containsKey(b.id),
    ))
      BathroomEntry(
        bathroom: bathroom,
        catalogueLabel: !communityEnabled
            ? null
            : !isShared(bathroom.id)
            ? 'Privado · por associar ao catálogo'
            : isAvailable(bathroom.id)
            ? 'Catálogo partilhado'
            : 'Envio pendente ou catálogo indisponível',
        activity: activityFor(bathroom.id),
        reviews: personalReviewsFor(bathroom.id),
        communityReviews: communityEnabled
            ? communityReviewsFor(bathroom.id)
            : null,
        visits: _visits,
      ),
  ];

  List<Review> personalReviewsFor(String id) => _reviews
      .where((r) => sharedIdentity(r.bathroomId) == sharedIdentity(id))
      .toList();

  BathroomActivity activityFor(String bathroomId) {
    _requireBathroom(bathroomId);
    final visits = visitsFor(bathroomId);
    return BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: [
        bathroomId,
        ...bathroomLinks.entries
            .where((e) => e.value == bathroomId)
            .map((e) => e.key),
      ].any((id) => _activities[(currentUserId, id)]?.isFavorite == true),
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
    _writable();
    materializeCatalogue();
    final previous = activityFor(bathroomId);
    final activity = BathroomActivity(
      userId: currentUserId,
      bathroomId: bathroomId,
      isFavorite: !previous.isFavorite,
    );
    final ids = [
      bathroomId,
      if (previous.isFavorite)
        ...bathroomLinks.entries
            .where((e) => e.value == bathroomId)
            .map((e) => e.key),
    ];
    _mutate(
      () => repository?.setRelatedFavourites(
        currentUserId,
        ids,
        activity.isFavorite,
      ),
      () {
        for (final id in ids) {
          _activities[(currentUserId, id)] = BathroomActivity(
            userId: currentUserId,
            bathroomId: id,
            isFavorite: activity.isFavorite,
          );
        }
      },
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
    _writable();
    if (!isAvailable(bathroomId)) {
      throw StateError('Catalogue contribution pending or unavailable');
    }
    materializeCatalogue();
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
    _writable();
    materializeCatalogue();
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
