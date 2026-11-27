import 'dart:math';
import 'auth_session.dart';
import 'namespace.dart';
import 'sync_store.dart';

export 'auth_session.dart';

enum RemoteFailureKind {
  transport,
  unavailableAuthentication,
  authorization,
  validation,
  conflict,
}

class RemoteFailure implements Exception {
  final RemoteFailureKind kind;
  final RemoteChange? conflict;
  const RemoteFailure(this.kind, {this.conflict});
}

class PullPage {
  final List<RemoteChange> changes;
  final String checkpoint;
  PullPage(List<RemoteChange> changes, this.checkpoint)
    : changes = List.unmodifiable(changes);
}

abstract interface class RemoteDataSource {
  Future<int> submit(SessionIdentity session, OutboxOperation operation);
  Future<PullPage> pull(
    DataNamespace namespace,
    String feed,
    String? checkpoint,
    int limit,
    SessionIdentity? session,
  );
}

/// Bounded execution; foreground lifecycle and consent belong to the controller.
class SyncCoordinator {
  final SyncStore store;
  final AuthSession auth;
  final RemoteDataSource remote;
  final int Function() now;
  final bool Function()? authorized;
  // The application prevents unseen pulls/acks from changing an open editor base.
  bool Function()? canApplyResults;
  int _epoch = 0, _activeEpoch = 0;
  void cancel() {
    _epoch++;
  }

  final double Function() jitter;
  final int batchSize, maxBackoffMs;
  static final _executionLocks = Expando<bool>();
  bool _running = false;
  int? _pausedGeneration;
  bool get isRunning => _running;
  RemoteFailureKind? lastFailure;
  bool moreWork = false;
  bool get authenticationRequired => _pausedGeneration == auth.generation;
  SyncCoordinator({
    required this.store,
    required this.auth,
    required this.remote,
    required this.now,
    this.authorized,
    double Function()? jitter,
    this.batchSize = 20,
    this.maxBackoffMs = 300000,
  }) : jitter = jitter ?? Random().nextDouble {
    if (batchSize < 1 || batchSize > 100 || maxBackoffMs < 1000) {
      throw ArgumentError('Invalid sync bounds');
    }
  }
  bool _valid(int generation) =>
      !store.local.isClosed &&
      _activeEpoch == _epoch &&
      (authorized?.call() ?? true) &&
      (canApplyResults?.call() ?? true) &&
      auth.generation == generation &&
      auth.current?.namespace == store.namespace &&
      auth.current!.expiresAt > now();

  Future<void> synchronize() async {
    if (store.local.isClosed ||
        _running ||
        _executionLocks[auth] == true ||
        !store.namespace.isAccount) {
      return;
    }
    final generation = auth.generation;
    _activeEpoch = _epoch;
    if (!_valid(generation) || _pausedGeneration == generation) return;
    _running = true;
    lastFailure = null;
    moreWork = false;
    _executionLocks[auth] = true;
    try {
      for (var count = 0; count < batchSize; count++) {
        if (!_valid(generation)) return;
        final ready = store.ready(now(), 1);
        if (ready.isEmpty) break;
        final op = ready.single;
        try {
          final revision = await remote.submit(auth.current!, op);
          if (!_valid(generation)) return;
          store.acknowledge(op, revision);
        } on RemoteFailure catch (error) {
          if (!_valid(generation)) return;
          lastFailure = error.kind;
          switch (error.kind) {
            case RemoteFailureKind.unavailableAuthentication:
              _pausedGeneration = generation;
              return;
            case RemoteFailureKind.transport:
              store.retry(op, now() + _delay(op.attempts), error.kind.name);
              return;
            case RemoteFailureKind.conflict:
              if (error.conflict == null) {
                throw StateError('Conflict requires remote revision');
              }
              store.reject(op, error.kind.name, conflict: error.conflict);
            case RemoteFailureKind.authorization:
            case RemoteFailureKind.validation:
              store.reject(op, error.kind.name);
          }
        }
      }
      if (!_valid(generation)) return;
      moreWork = store.ready(now(), 1).isNotEmpty;
      await _pull('private', generation, auth.current);
    } finally {
      _running = false;
      _executionLocks[auth] = false;
    }
  }

  Future<void> refreshPublicCatalogue() async {
    if (store.local.isClosed ||
        _running ||
        _executionLocks[auth] == true ||
        store.namespace.kind != 'public') {
      return;
    }
    _running = true;
    _executionLocks[auth] = true;
    try {
      await _pull('catalogue', null, null);
    } finally {
      _running = false;
      _executionLocks[auth] = false;
    }
  }

  int _delay(int attempts) {
    final ceiling = min(maxBackoffMs, 1000 * (1 << min(attempts, 20)));
    return max(1, (ceiling * (0.5 + jitter().clamp(0.0, 1.0) * 0.5)).round());
  }

  Future<void> _pull(
    String feed,
    int? generation,
    SessionIdentity? session,
  ) async {
    if (!store.pullAllowed(feed, now())) return;
    try {
      final page = await remote.pull(
        store.namespace,
        feed,
        store.checkpoint(feed),
        batchSize,
        session,
      );
      if (store.local.isClosed || (generation != null && !_valid(generation))) {
        return;
      }
      if (page.changes.length > batchSize) {
        throw StateError('Remote exceeded pull limit');
      }
      store.applyPull(feed, page.changes, page.checkpoint);
      moreWork = moreWork || page.changes.length == batchSize;
    } on RemoteFailure catch (error) {
      if (store.local.isClosed || (generation != null && !_valid(generation))) {
        return;
      }
      lastFailure = error.kind;
      switch (error.kind) {
        case RemoteFailureKind.unavailableAuthentication:
          _pausedGeneration = generation;
        case RemoteFailureKind.transport:
          store.failPull(
            feed,
            error.kind.name,
            now() + _delay(store.pullAttempts(feed)),
          );
        case RemoteFailureKind.authorization:
        case RemoteFailureKind.validation:
          store.failPull(feed, error.kind.name, now(), blocked: true);
        case RemoteFailureKind.conflict:
          throw StateError('Pull cannot return a mutation conflict');
      }
    }
  }
}

/// Deterministic protocol double, not evidence of server implementation.
class FakeRemoteDataSource implements RemoteDataSource {
  final Map<String, (String, int)> _receipts = {};
  final List<OutboxOperation> requests = [];
  final List<RemoteFailure> failures = [];
  final List<RemoteFailure> pullFailures = [];
  final List<String?> pullRequests = [];
  Future<void> Function()? beforePull;
  final Map<String, PullPage> pages = {};
  Future<void> Function()? beforeSubmit;
  bool loseNextAcknowledgment = false;
  int applications = 0;
  @override
  Future<int> submit(SessionIdentity session, OutboxOperation operation) async {
    if (session.namespace != operation.namespace) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    requests.add(operation);
    await beforeSubmit?.call();
    if (failures.isNotEmpty) throw failures.removeAt(0);
    final key = '${operation.namespace.key}:${operation.id}';
    final fingerprint =
        '${operation.type}:${operation.entityType}:${operation.entityId}:${operation.baseRevision}:${operation.payload}:${operation.dependencies}';
    final existing = _receipts[key];
    if (existing != null) {
      if (existing.$1 != fingerprint) {
        throw const RemoteFailure(RemoteFailureKind.validation);
      }
      return existing.$2;
    }
    final revision = ++applications;
    _receipts[key] = (fingerprint, revision);
    if (loseNextAcknowledgment) {
      loseNextAcknowledgment = false;
      throw const RemoteFailure(RemoteFailureKind.transport);
    }
    return revision;
  }

  @override
  Future<PullPage> pull(
    DataNamespace namespace,
    String feed,
    String? checkpoint,
    int limit,
    SessionIdentity? session,
  ) async {
    if (namespace.isAccount && session?.namespace != namespace) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    pullRequests.add(checkpoint);
    await beforePull?.call();
    if (pullFailures.isNotEmpty) throw pullFailures.removeAt(0);
    return pages['${namespace.key}:$feed'] ??
        PullPage([], checkpoint ?? 'initial');
  }
}
