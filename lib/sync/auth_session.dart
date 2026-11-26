import 'package:flutter/foundation.dart';
import 'namespace.dart';

class SessionIdentity {
  final DataNamespace namespace;
  final int expiresAt;
  const SessionIdentity(this.namespace, this.expiresAt);
}

enum SessionStatus { unauthenticated, authenticated, expired, invalidated }

/// Identity only: never grants association, synchronization or publication.
/// Adapters notify and advance generation on renewal, expiry and invalidation,
/// including logout and switching away and back to the same subject.
abstract interface class AuthSession implements Listenable {
  SessionIdentity? get current;
  int get generation;
  SessionStatus get status;
}

/// Memory-only adapter. No credentials, network, persistence or auth method.
class FakeAuthSession extends ChangeNotifier implements AuthSession {
  final int Function() now;
  FakeAuthSession({int Function()? now})
    : now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  bool _disposed = false;
  SessionIdentity? _current;
  @override
  SessionIdentity? get current => _current;
  int _generation = 0;
  @override
  int get generation => _generation;
  SessionStatus _status = SessionStatus.unauthenticated;
  @override
  SessionStatus get status => _current != null && _current!.expiresAt <= now()
      ? SessionStatus.expired
      : _status;

  void change(SessionIdentity? identity) {
    if (_disposed) throw StateError('Session is disposed');
    if (identity != null && !identity.namespace.isAccount) {
      throw ArgumentError('Authenticated identity requires an account scope');
    }
    _current = identity;
    _status = identity == null
        ? SessionStatus.unauthenticated
        : (identity.expiresAt <= now()
              ? SessionStatus.expired
              : SessionStatus.authenticated);
    _generation++;
    notifyListeners();
  }

  void logout() => change(null);

  void invalidate() {
    if (_disposed) throw StateError('Session is disposed');
    _current = null;
    _status = SessionStatus.invalidated;
    _generation++;
    notifyListeners();
  }

  /// Explicit clock event; a real adapter must also handle resume/expiry events.
  void checkExpiry() {
    if (_disposed) return;
    if (_current != null &&
        _current!.expiresAt <= now() &&
        _status != SessionStatus.expired) {
      _status = SessionStatus.expired;
      _generation++;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _current = null;
    _status = SessionStatus.invalidated;
    _generation++;
    super.dispose();
  }

  /// A delayed renewal cannot restore a logged-out or different session.
  Future<bool> renew(
    Future<SessionIdentity> Function(SessionIdentity) renewal,
  ) async {
    if (_disposed) return false;
    final identity = _current;
    if (identity == null) return false;
    final generation = _generation;
    final renewed = await renewal(identity);
    if (_generation != generation) return false;
    if (renewed.namespace != identity.namespace || renewed.expiresAt <= now()) {
      throw StateError('Renewal must retain identity and extend validity');
    }
    change(renewed);
    return true;
  }
}
