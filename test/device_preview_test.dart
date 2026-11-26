import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../tool/auth_device_preview.dart';

void main() {
  test(
    'device target accepts only its isolated HTTPS Auth endpoint and client',
    () {
      expect(
        devicePreviewConfiguration(
          'https://localhost:55474',
          'local-device-client',
        ).environment,
        'https://localhost:55474',
      );
      for (final endpoint in [
        'http://localhost:55474',
        'https://127.0.0.1:55474',
        'https://managed.example',
        'https://localhost:55474/other',
      ]) {
        expect(
          () => devicePreviewConfiguration(endpoint, 'local-device-client'),
          throwsArgumentError,
        );
      }
      expect(
        () => devicePreviewConfiguration(
          'https://localhost:55474',
          'sb_secret_test',
        ),
        throwsArgumentError,
      );
    },
  );

  test('local TLS gateway validates certificate trust and hostname', () async {
    final directory = Platform.environment['BATH_DEVICE_TLS_DIRECTORY']!;
    final configuration =
        jsonDecode(File('$directory/defines.json').readAsStringSync())
            as Map<String, dynamic>;
    final encoded = configuration['BATH_DEVICE_CA_BASE64'] as String;
    final tls = DevicePreviewTls(encoded);
    Future<int> health(
      HttpClient client,
      String host, [
      String path = '/auth/v1/health',
    ]) async {
      try {
        final request = await client.getUrl(
          Uri.parse('https://$host:55474$path'),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    await expectLater(
      health(HttpClient(), 'localhost'),
      throwsA(isA<HandshakeException>()),
    );
    expect(await health(tls.createHttpClient(null), 'localhost'), 200);
    expect(
      await health(tls.createHttpClient(null), 'localhost', '/rest/v1/'),
      404,
    );
    await expectLater(
      health(tls.createHttpClient(null), '127.0.0.1'),
      throwsA(isA<HandshakeException>()),
    );
  }, skip: Platform.environment['BATH_DEVICE_TLS_DIRECTORY'] == null);
}
