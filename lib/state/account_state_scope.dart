import 'package:flutter/foundation.dart';
import '../storage/bathroom_repository.dart';
import '../storage/local_store.dart';
import '../sync/auth_session.dart';
import '../sync/namespace.dart';
import '../sync/sync_store.dart';
import 'app_state.dart';

/// Owns the authenticated device state or an explicitly injected test context.
/// Owns one selected state/connection; identity events alone never open stores,
/// associate guest data, authorize an outbox or execute synchronization.
class AccountStateScope extends ChangeNotifier {
  final bool offlineAccess;
  final bool accountOnly;
  final AuthSession auth;
  final Future<LocalStore> Function(DataNamespace) openStore;
  final int Function() now;
  AccountStateScope.forTesting({
    this.offlineAccess = false,
    this.accountOnly = false,
    required this.auth,
    required this.openStore,
    required this.now,
  }) {
    auth.addListener(_sessionChanged);
  }

  AccountStateScope.device({
    required AuthSession auth,
    required Future<LocalStore> Function(DataNamespace) openStore,
  }) : this.forTesting(
         auth: auth,
         openStore: openStore,
         offlineAccess: true,
         accountOnly: true,
         now: () => DateTime.now().millisecondsSinceEpoch,
       );

  AppState? _state;
  AppState? get state => _state;
  LocalStore? _store;
  int _selection = 0;
  bool _disposed = false;

  /// An expired/foreign session hides the retained editor tree. It does not
  /// discard memory-only work or automatically select another person's data.
  bool get isAccessible =>
      !_disposed &&
      _store != null &&
      _matchesSession(_store!.namespace) &&
      (!offlineAccess || _store!.namespace.isAccount || auth.current == null);

  bool _matchesSession(DataNamespace namespace) =>
      namespace.kind == 'guest' ||
      (namespace.isAccount &&
          auth.current?.namespace == namespace &&
          (offlineAccess || auth.current!.expiresAt > now()));

  void _sessionChanged() {
    if (!_disposed) notifyListeners();
  }

  void _guardReplacement() {
    if (_disposed) throw StateError('Account state scope is disposed');
    if (_state?.hasUncommittedWork == true) {
      throw StateError(
        'Finish the open editor or retry the local commit first',
      );
    }
  }

  /// Selection/logout policy is deliberately test-only. A caller must finish
  /// editors and retry failed transactions; there is no implicit discard path.
  /// Optional test queueing is separate from authentication and never inferred.
  Future<bool> select(
    DataNamespace namespace, {
    SyncWriteContext? synchronizationForTesting,
  }) async {
    _guardReplacement();
    if (accountOnly && !namespace.isAccount) {
      throw StateError(
        'Device access requires an account; legacy files are preserved',
      );
    }
    if (synchronizationForTesting != null &&
        (!namespace.isAccount ||
            synchronizationForTesting.namespace != namespace)) {
      throw ArgumentError('Synchronization fixture must match account scope');
    }
    if (!_matchesSession(namespace)) {
      throw StateError('A valid matching account session is required');
    }
    final selection = ++_selection;
    if (_store?.namespace == namespace) return true;
    final generation = auth.generation;
    final store = await openStore(namespace);
    AppState? next;
    try {
      if (store.namespace != namespace) {
        throw StateError('Opener returned a different namespace');
      }
      if (_disposed ||
          selection != _selection ||
          generation != auth.generation ||
          !_matchesSession(namespace)) {
        store.close();
        return false;
      }
      _guardReplacement(); // An editor may have opened during the await.
      next = namespace.isAccount
          ? AppState.restoreAccountForTesting(
              BathroomRepository(store, syncContext: synchronizationForTesting),
            )
          : AppState.restore(store);
    } catch (_) {
      next?.dispose();
      store.close();
      rethrow;
    }
    final previousState = _state;
    final previousStore = _store;
    _state = next;
    _store = store;
    previousState?.dispose();
    previousStore?.close();
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _guardReplacement();
    _disposed = true;
    _selection++;
    auth.removeListener(_sessionChanged);
    _state?.dispose();
    _store?.close();
    super.dispose();
  }
}
