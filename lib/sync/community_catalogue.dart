import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/bathroom.dart';
import '../models/community_review.dart';
import '../storage/local_store.dart';
import 'sync_coordinator.dart';

/// One environment-scoped, anonymous, durable cache. No personal records enter it.
class CommunityCatalogue extends ChangeNotifier {
  final SyncCoordinator coordinator;
  final VoidCallback? closeRemote;
  CommunityCatalogue(this.coordinator, {this.closeRemote});
  LocalStore get local => coordinator.store.local;
  bool running = false, _disposed = false;
  bool _foreground = true;
  Timer? _retry;
  Future<void>? _refreshing;
  String? error;
  List<Map<String, dynamic>> _rows(String type) => [
    for (final row in local.database.select(
      'SELECT payload FROM remote_records WHERE entity_type=? AND deleted=0',
      [type],
    ))
      Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
  ];
  List<Bathroom> get bathrooms => [
    for (final p in _rows('bathroom'))
      Bathroom(
        id: p['id'] as String,
        name: p['name'] as String,
        createdBy: 'catalogue',
        classification: p['classification'] as String? ?? 'community',
        emoji: p['emoji'] as String,
        accent: p['accent'] as int,
        accentRgb: p['accent_rgb'] as int?,
      ),
  ];
  List<CommunityReview> get reviews =>
      _rows('review').map(CommunityReview.fromJson).toList();
  bool get hasCache => coordinator.store.checkpoint('catalogue') != null;
  void foreground(bool value) {
    _foreground = value;
    _retry?.cancel();
    if (value) refresh();
  }

  Future<void> refresh() {
    if (_disposed || !_foreground) return Future.value();
    if (_refreshing case final pending?) return pending;
    // Publish the future before notifying listeners: a listener can itself
    // request a refresh synchronously, before the first network await.
    final completion = Completer<void>();
    _refreshing = completion.future;
    unawaited(
      _refresh().then(
        (_) {
          _refreshing = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _refreshing = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _refresh() async {
    _retry?.cancel();
    running = true;
    error = null;
    notifyListeners();
    try {
      coordinator.store.retryPull('catalogue');
      // Bounded pages; continue on a short one-shot timer for larger catalogues.
      coordinator.moreWork = false;
      coordinator.lastFailure = null;
      await coordinator.refreshPublicCatalogue();
      if (_disposed) return;
      if (coordinator.lastFailure != null) {
        error = 'Catálogo indisponível. Podes consultar os dados já guardados.';
      }
    } catch (_) {
      if (!_disposed) {
        error =
            'Não foi possível atualizar o catálogo. Os dados guardados continuam disponíveis.';
      }
    } finally {
      running = false;
      if (!_disposed) {
        notifyListeners();
        if (_foreground && (error != null || coordinator.moreWork)) {
          _retry = Timer(
            Duration(milliseconds: error == null ? 300 : 30000),
            refresh,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    closeRemote?.call();
    local.close();
    super.dispose();
  }
}
