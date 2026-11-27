import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bath_royale/sync/http_remote_data_source.dart';

void main() {
  test('feedback HTTP sends no authentication or account context', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? body;
    String? authorization;
    server.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"submitted":true}');
      await request.response.close();
    });
    final remote = HttpRemoteDataSource.forTesting(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      environment: 'feedback-test',
      accessToken: (_) => throw StateError('Must never request a token'),
    );
    addTearDown(remote.close);
    final payload = {
      'report_id': 'report',
      'retry_key': 'retry',
      'category': 'problem',
      'description': 'Feedback',
      'app_version': '0.1.0',
      'platform_version': 'Android 16',
      'screen_id': 'explore',
    };
    await remote.submitFeedback(payload);
    expect(body, payload);
    expect(authorization, isNull);
  });
}
