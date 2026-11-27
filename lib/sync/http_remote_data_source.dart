import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'namespace.dart';
import 'sync_coordinator.dart';
import 'sync_store.dart';

/// Authenticated synchronization RPC transport; never receives refresh tokens.
class HttpRemoteDataSource implements RemoteDataSource {
  final Uri endpoint;
  final String environment;
  final String? Function(SessionIdentity) accessToken;
  final HttpClient _client;
  final String? clientKey;
  HttpRemoteDataSource({
    required this.endpoint,
    required this.environment,
    required this.accessToken,
    this.clientKey,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  HttpRemoteDataSource.forTesting({
    required this.endpoint,
    required this.environment,
    required this.accessToken,
    HttpClient? client,
  }) : clientKey = null,
       _client = client ?? HttpClient();

  void close() => _client.close(force: true);

  void _scope(DataNamespace namespace) {
    if (namespace.environment != environment) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String name,
    Map<String, Object?> body,
    SessionIdentity? session,
  ) async {
    final token = session == null ? null : accessToken(session);
    if (session != null && token == null) {
      throw const RemoteFailure(RemoteFailureKind.unavailableAuthentication);
    }
    try {
      final request = await _client
          .postUrl(endpoint.resolve('rpc/$name'))
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      if (clientKey != null) request.headers.set('apikey', clientKey!);
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final bytes = utf8.encode(jsonEncode(body));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        throw const RemoteFailure(RemoteFailureKind.unavailableAuthentication);
      }
      if (response.statusCode == 403) {
        throw const RemoteFailure(RemoteFailureKind.authorization);
      }
      if (response.statusCode == 429 || response.statusCode >= 500) {
        throw const RemoteFailure(RemoteFailureKind.transport);
      }
      if (response.statusCode != 200) {
        throw const RemoteFailure(RemoteFailureKind.validation);
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on IOException {
      throw const RemoteFailure(RemoteFailureKind.transport);
    } on TimeoutException {
      throw const RemoteFailure(RemoteFailureKind.transport);
    }
  }

  /// Narrow anonymous write capability: no account session or history is sent.
  Future<void> submitFeedback(Map<String, Object?> payload) async {
    final result = await _rpc('submit_alpha_feedback', payload, null);
    if (result['submitted'] != true) {
      throw const RemoteFailure(RemoteFailureKind.transport);
    }
  }

  Future<List<Map<String, dynamic>>> feedbackReports(
    SessionIdentity session,
    int page,
  ) async {
    _scope(session.namespace);
    final result = await _rpc('alpha_feedback_reports', {
      'page': page,
    }, session);
    return (result['reports'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> setFeedbackStatus(
    SessionIdentity session,
    String id,
    String status,
  ) async {
    _scope(session.namespace);
    await _rpc('set_alpha_feedback_status', {
      'report_id': id,
      'new_status': status,
    }, session);
  }

  Future<List<Map<String, dynamic>>> moderationReports(
    SessionIdentity session,
  ) async {
    _scope(session.namespace);
    final result = await _rpc('moderation_reports', {}, session);
    return (result['reports'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> moderateContent(
    SessionIdentity session,
    String kind,
    String id,
    bool hide,
    String reportId,
  ) async {
    _scope(session.namespace);
    await _rpc('moderate_content', {
      'content_kind': kind,
      'content_id': id,
      'hide': hide,
      'report_id': reportId,
    }, session);
  }

  Future<void> grantBathroomCreation(
    SessionIdentity session,
    String email,
    bool allowed,
  ) async {
    _scope(session.namespace);
    await _rpc('grant_bathroom_creation', {
      'account_email': email,
      'allowed': allowed,
    }, session);
  }

  static RemoteChange _change(Map<String, dynamic> value) => RemoteChange(
    value['entityType'] as String,
    value['entityId'] as String,
    value['revision'] as int,
    deleted: value['deleted'] as bool,
    payload: Map<String, Object?>.from(value['payload'] as Map),
  );

  @override
  Future<int> submit(SessionIdentity session, OutboxOperation operation) async {
    _scope(operation.namespace);
    if (session.namespace != operation.namespace) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    final result = await _rpc('sync_submit', {
      'command': {
        'operationId': operation.id,
        'entityType': operation.entityType,
        'entityId': operation.entityId,
        'type': operation.type,
        'payload': jsonDecode(operation.payload),
        'baseRevision': operation.baseRevision,
        'dependencies': operation.dependencies,
      },
    }, session);
    if (result['subject'] != session.namespace.subject) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    if (result['status'] == 'conflict') {
      throw RemoteFailure(
        RemoteFailureKind.conflict,
        conflict: _change(result['conflict'] as Map<String, dynamic>),
      );
    }
    if (result['status'] != 'acknowledged') {
      throw StateError('Invalid acknowledgment');
    }
    final revision = result['revision'] as int;
    final entities = (result['entities'] as List).cast<Map<String, dynamic>>();
    // The int contract means all affected entities must share one revision.
    if (entities.isEmpty || entities.any((e) => e['revision'] != revision)) {
      throw StateError('Inconsistent command revisions');
    }
    final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
    final targets = <(String, String)>[
      (operation.entityType, operation.entityId),
    ];
    if (payload['visit'] case final Map<String, dynamic> visit) {
      targets.add(('visit', visit['id'] as String));
    }
    if (payload['review'] case final Map<String, dynamic> review) {
      targets.add(('visit', review['visit'] as String));
    }
    if (payload['deletedReviewId'] case final String id) {
      targets.add(('review', id));
    }
    for (final (type, id) in targets) {
      if (!entities.any(
        (e) => e['entityType'] == type && e['entityId'] == id,
      )) {
        throw StateError('Incomplete command acknowledgment');
      }
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
    _scope(namespace);
    if ((namespace.isAccount &&
            (feed != 'private' || session?.namespace != namespace)) ||
        (namespace.kind == 'public' && feed != 'catalogue') ||
        namespace.kind == 'guest') {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    final result = await _rpc('sync_pull', {
      'feed': feed,
      'checkpoint': checkpoint,
      'page_size': limit,
    }, session);
    if (namespace.isAccount && result['subject'] != namespace.subject) {
      throw const RemoteFailure(RemoteFailureKind.authorization);
    }
    return PullPage(
      (result['changes'] as List)
          .map((e) => _change(e as Map<String, dynamic>))
          .toList(),
      result['checkpoint'] as String,
    );
  }
}
