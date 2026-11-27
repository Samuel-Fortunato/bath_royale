import '../models/bathroom.dart';
import '../models/provenance.dart';
import '../models/review.dart';
import '../models/visit.dart';
import '../sync/sync_store.dart';
import 'local_store.dart';

/// Local transactional action boundary. Queueing is separate from transfer consent.
class BathroomRepository {
  final LocalStore store;
  final SyncWriteContext? syncContext;
  BathroomRepository(this.store, {this.syncContext}) {
    if (store.namespace.kind == 'public' ||
        (syncContext != null &&
            (!store.namespace.isAccount ||
                syncContext!.namespace != store.namespace))) {
      throw ArgumentError('Invalid mutation namespace');
    }
  }
  SyncStore get _sync => SyncStore(store);
  LocalData? load() => store.load();
  void initialize(LocalData data) => store.initialize(data);

  Map<String, Object?> _row(String table, String id) => Map.of(
    store.database.select('SELECT * FROM $table WHERE id=?', [id]).single,
  );
  bool _eligible(Map<String, Object?> row) =>
      row['provenance'] == Provenance.userCreated.value ||
      (store.namespace.isAccount &&
          row['provenance'] == Provenance.remote.value);
  void _queue(
    String type,
    String id,
    String command,
    Map<String, Object?> payload, {
    required bool eligible,
    List<(String, String)> references = const [],
  }) {
    if (syncContext != null && eligible) {
      _sync.enqueue(type, id, command, payload, references: references);
    }
  }

  void _owner(String owner) {
    if (store.namespace.isAccount && owner != store.namespace.subject) {
      throw StateError('Identity outside account namespace');
    }
  }

  void createBathroom(Bathroom b) => store.transaction(() {
    _owner(b.createdBy);
    store.insertBathroom(b, provenance: Provenance.userCreated);
    final row = _row('bathrooms', b.id);
    _queue('bathroom', b.id, 'createBathroom', row, eligible: _eligible(row));
  });
  void updateBathroom(Bathroom b) => store.transaction(() {
    _owner(b.createdBy);
    store.updateBathroom(b);
    final row = _row('bathrooms', b.id);
    _queue('bathroom', b.id, 'updateBathroom', row, eligible: _eligible(row));
  });
  void recordVisit(Visit v) => store.transaction(() {
    _owner(v.userId);
    store.insertVisit(v);
    final row = _row('visits', v.id);
    _queue(
      'visit',
      v.id,
      'createVisit',
      row,
      eligible: _eligible(row),
      references: [('bathroom', v.bathroomId)],
    );
  });
  void deleteVisit(String id) => store.transaction(() {
    final row = _row('visits', id);
    _owner(row['user'] as String);
    final reviews = store.database.select(
      'SELECT id FROM reviews WHERE visit=?',
      [id],
    );
    final reviewId = reviews.isEmpty ? null : reviews.single['id'] as String;
    store.removeVisit(id);
    _queue(
      'visit',
      id,
      'deleteVisit',
      {'id': id, 'deletedReviewId': reviewId},
      eligible: _eligible(row),
      references: [if (reviewId != null) ('review', reviewId)],
    );
  });
  void saveReview(Review r, {Visit? newVisit, required bool isNew}) =>
      store.transaction(() {
        _owner(r.authorId);
        if (newVisit != null) {
          if (!isNew ||
              newVisit.id != r.visitId ||
              newVisit.bathroomId != r.bathroomId ||
              newVisit.userId != r.authorId) {
            throw ArgumentError('Compound review must match its new visit');
          }
          _owner(newVisit.userId);
          store.insertVisit(newVisit);
        }
        store.writeReview(r, isNew: isNew);
        final row = _row('reviews', r.id);
        _queue(
          'review',
          r.id,
          newVisit != null
              ? 'createVisitReview'
              : (isNew ? 'createReview' : 'updateReview'),
          {
            'review': row,
            if (newVisit != null) 'visit': _row('visits', newVisit.id),
          },
          eligible: _eligible(row),
          references: [('bathroom', r.bathroomId), ('visit', r.visitId)],
        );
      });
  void setFavourite(String user, String bathroom, bool value) =>
      store.transaction(() => _setFavourite(user, bathroom, value));
  void setRelatedFavourites(String user, List<String> ids, bool value) =>
      store.transaction(() {
        for (final id in ids) {
          _setFavourite(user, id, value);
        }
      });
  void _setFavourite(String user, String bathroom, bool value) {
    _owner(user);
    final existing = store.database.select(
      'SELECT provenance FROM favourites WHERE user=? AND bathroom=?',
      [user, bathroom],
    );
    final eligible =
        store.bathroomProvenance(bathroom).child.allowsFutureUpload &&
        (existing.isEmpty ||
            [
              Provenance.userCreated.value,
              Provenance.remote.value,
            ].contains(existing.single['provenance']));
    store.setFavourite(user, bathroom, value);
    _queue(
      'favourite',
      bathroom,
      'setFavourite',
      {'user': user, 'bathroom': bathroom, 'value': value},
      eligible: eligible,
      references: [('bathroom', bathroom)],
    );
  }

  void setDarkMode(bool value) =>
      store.transaction(() => store.setDarkMode(value));
}
