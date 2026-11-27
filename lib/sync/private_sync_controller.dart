import 'dart:async';
import 'package:flutter/foundation.dart';
import '../state/app_state.dart';
import 'account_projection.dart';
import 'sync_coordinator.dart';
import 'sync_store.dart';

/// Foreground events and one-shot retries only while work remains. No idle polling.
class PrivateSyncController extends ChangeNotifier {
  final AppState state;
  final SyncCoordinator coordinator;
  final Future<void> Function() renew;
  final Future<bool> Function()? refreshSession;
  final void Function()? closeRemote;
  SyncStore get store => coordinator.store;
  PrivateSyncController({
    required this.state,
    required this.coordinator,
    required this.renew,
    this.refreshSession,
    this.closeRemote,
  }) {
    coordinator.canApplyResults = () => !_disposed && !state.hasUncommittedWork;
    state.addListener(request);
    coordinator.auth.addListener(request);
  }
  Timer? _timer;
  bool _disposed = false,
      _foreground = true,
      _running = false,
      _requested = false,
      _applying = false;
  bool get running => _running;
  String? error;
  bool get enabled => store.hasConsent;
  bool get _accessible =>
      coordinator.auth.current?.namespace == store.namespace;

  String get status {
    if (!enabled) return 'Aceita o armazenamento da conta para continuar';
    if (running) return 'A sincronizar…';
    if (state.hasUncommittedWork) {
      return 'Termina o editor ou a gravação local para sincronizar.';
    }
    if (store.problems.isNotEmpty) {
      return 'Há alterações que precisam de atenção';
    }
    if (error != null) return error!;
    if (store.pullBlocked) {
      return 'Não foi possível receber os dados. Tenta sincronizar ou recarregar os dados da conta.';
    }
    if (store.pendingCount > 0) {
      return '${store.pendingCount} alterações pendentes';
    }
    return 'Sincronização privada em dia';
  }

  void acceptStorage() {
    store.consent();
    request();
    notifyListeners();
  }

  Future<void> enable() async {
    acceptStorage();
    await synchronize();
  }

  void foreground(bool value) {
    _foreground = value;
    if (!value) {
      coordinator.cancel();
      _timer?.cancel();
    } else {
      request();
    }
  }

  void request() {
    if (_disposed ||
        _applying ||
        state.hasUncommittedWork ||
        !_foreground ||
        !enabled ||
        !_accessible) {
      return;
    }
    if (_running) {
      _requested = true;
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), synchronize);
  }

  Future<void> replay() async {
    store.resetPrivateCheckpoint();
    await retry();
  }

  Future<void> retry() async {
    store.retryNow();
    await synchronize();
  }

  Future<void> synchronize() async {
    if (_disposed ||
        state.hasUncommittedWork ||
        !_foreground ||
        !enabled ||
        !_accessible ||
        _running) {
      return;
    }
    var authenticationBlocked = false;
    var authenticationUnavailable = false;
    var unexpectedFailure = false;
    _running = true;
    _requested = false;
    error = null;
    notifyListeners();
    try {
      await renew();
      if (_disposed || !enabled || !_accessible || !_foreground) return;
      if (coordinator.auth.current!.expiresAt <= coordinator.now()) {
        authenticationUnavailable = true;
        error =
            'Sem ligação ou sessão expirada. Os dados continuam guardados; tenta renovar a sessão na tua conta.';
        return;
      }
      await coordinator.synchronize();
      if (_disposed || !_accessible) return;
      if (!state.hasUncommittedWork) {
        // Reload only after an atomic projection. Open forms are never replaced.
        _applying = true;
        try {
          // Reflect acknowledged contributions/publication without requiring a
          // manual catalogue refresh. Suppress notifications from scheduling
          // another idle account run while refreshing this public projection.
          if (coordinator.lastFailure == null &&
              !coordinator.authenticationRequired) {
            await state.community?.refresh();
          }
          if (_disposed || !_accessible || !_foreground) return;
          if (!state.hasUncommittedWork) {
            state.materializeCatalogue();
            AccountProjection(store).apply();
            state.reloadAccountData();
          }
        } finally {
          _applying = false;
        }
      }
      if (coordinator.authenticationRequired) {
        final refreshed = await refreshSession?.call() ?? false;
        if (_disposed || !_accessible) return;
        if (refreshed) {
          _requested = true;
        } else {
          authenticationBlocked = true;
          error =
              'A sessão precisa de ser renovada. Entra novamente na tua conta; as alterações estão guardadas.';
        }
      } else if (coordinator.lastFailure == RemoteFailureKind.transport) {
        error =
            'Sem ligação ao serviço. As alterações estão guardadas e voltaremos a tentar.';
      } else if (coordinator.lastFailure != null) {
        error =
            'Não foi possível sincronizar. Revê as alterações ou tenta novamente.';
      }
    } catch (_) {
      unexpectedFailure = true;
      error =
          'Não foi possível sincronizar. Os dados locais foram preservados. Tenta novamente.';
    } finally {
      _running = false;
      if (!_disposed) {
        notifyListeners();
        _timer?.cancel();
        if (enabled &&
            _accessible &&
            _foreground &&
            !authenticationBlocked &&
            !unexpectedFailure) {
          final next = store.nextAttempt;
          final delayed = coordinator.authenticationRequired ? null : next;
          if (authenticationUnavailable) {
            // Ready outbox rows cannot bypass Auth retry pacing while offline.
            _timer = Timer(const Duration(seconds: 30), synchronize);
          } else if (error == null && (coordinator.moreWork || _requested)) {
            _timer = Timer(const Duration(milliseconds: 300), synchronize);
          } else if (delayed != null ||
              coordinator.lastFailure == RemoteFailureKind.transport &&
                  !coordinator.authenticationRequired) {
            final delay = delayed == null
                ? 30000
                : (delayed - coordinator.now()).clamp(1000, 300000);
            _timer = Timer(Duration(milliseconds: delay), synchronize);
          }
        }
      }
    }
  }

  void useAccountVersion(String id) {
    store.useAccountVersion(id);
    AccountProjection(store).apply();
    state.reloadAccountData();
    request();
    notifyListeners();
  }

  void resend(String id, {String? correctedText}) {
    store.retryProblem(id, correctedText: correctedText);
    if (correctedText != null) state.reloadAccountData();
    request();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    state.removeListener(request);
    coordinator.auth.removeListener(request);
    closeRemote?.call();
    super.dispose();
  }
}
