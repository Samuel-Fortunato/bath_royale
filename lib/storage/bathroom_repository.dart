import '../models/bathroom.dart';
import '../models/provenance.dart';
import '../models/review.dart';
import '../models/visit.dart';
import 'local_store.dart';

/// Small local action boundary. No accounts, transport or synchronization.
class BathroomRepository {
  final LocalStore store;
  BathroomRepository(this.store);

  LocalData? load() => store.load();
  void initialize(LocalData data) => store.initialize(data);
  void createBathroom(Bathroom b) => store.transaction(
    () => store.insertBathroom(b, provenance: Provenance.userCreated),
  );
  void updateBathroom(Bathroom b) =>
      store.transaction(() => store.updateBathroom(b));
  void recordVisit(Visit v) => store.transaction(() => store.insertVisit(v));
  void deleteVisit(String id) => store.transaction(() => store.removeVisit(id));
  void saveReview(Review r, {Visit? newVisit, required bool isNew}) =>
      store.transaction(() {
        if (newVisit != null) store.insertVisit(newVisit);
        store.writeReview(r, isNew: isNew);
      });
  void setFavourite(String user, String bathroom, bool value) =>
      store.transaction(() => store.setFavourite(user, bathroom, value));
  void setDarkMode(bool value) =>
      store.transaction(() => store.setDarkMode(value));
}
