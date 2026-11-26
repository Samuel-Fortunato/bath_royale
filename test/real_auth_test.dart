import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/auth/restoration_guard.dart';
import 'package:bath_royale/sync/auth_session.dart';
import 'production_auth_test.dart' show MemoryVault;
import '../tool/auth_device_preview.dart';

void main() {
  test(
    'isolated real registration, confirmation, recovery, rotation and logout',
    () async {
      final vault = MemoryVault();
      final directory = Directory.systemTemp.createTempSync('bath-real-auth-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final deviceDirectory = Platform.environment['BATH_DEVICE_TLS_DIRECTORY'];
      final gateway = deviceDirectory != null;
      if (gateway) {
        final defines =
            jsonDecode(File('$deviceDirectory/defines.json').readAsStringSync())
                as Map;
        final previous = HttpOverrides.current;
        HttpOverrides.global = DevicePreviewTls(
          defines['BATH_DEVICE_CA_BASE64'] as String,
        );
        addTearDown(() => HttpOverrides.global = previous);
      }
      final config = gateway
          ? devicePreviewConfiguration(
              'https://localhost:55474',
              'local-device-client',
            )
          : AuthConfiguration(
              'http://127.0.0.1:55471',
              'local-client',
              localTest: true,
            );
      final sdkEndpoint = gateway
          ? '${config.environment}/auth/v1'
          : config.environment;
      String mappedLink(Uri link) => link
          .replace(
            scheme: config.endpoint.scheme,
            host: config.endpoint.host,
            port: config.endpoint.port,
            path: '/auth/v1/verify',
          )
          .toString();
      ProductionAuth make() => ProductionAuth(
        config,
        vault,
        restorationGuard: PlatformRestorationGuard(
          directory: () async => directory,
        ),
        now: () => DateTime.now().millisecondsSinceEpoch + 45000,
        client: GoTrueClient(
          url: sdkEndpoint,
          flowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      );
      var auth = make();
      final email = 'auth-${DateTime.now().microsecondsSinceEpoch}@example.com';
      const password = 'Fictional-only-Passphrase-7482';
      Future<dynamic> mail(String path) async {
        final http = HttpClient();
        try {
          final request = await http.getUrl(
            Uri.parse('http://127.0.0.1:55473/api/v1/$path'),
          );
          final response = await request.close();
          return jsonDecode(await utf8.decoder.bind(response).join());
        } finally {
          http.close(force: true);
        }
      }

      Future<String> link() async {
        for (var i = 0; i < 30; i++) {
          final listing = await mail('messages') as Map;
          for (final item in listing['messages'] as List) {
            final message = await mail('message/${item['ID']}') as Map;
            if (!(message['To'] as List).any((e) => e['Address'] == email)) {
              continue;
            }
            final text = '${message['Text']} ${message['HTML']}';
            final match = RegExp(
              r'http://127\.0\.0\.1:55471/verify\?[^\s"<>]+',
            ).firstMatch(text);
            if (match != null) return match.group(0)!.replaceAll('&amp;', '&');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        throw StateError('No captured email');
      }

      await auth.restore();
      await auth.register(email, password);
      expect(auth.current, isNull, reason: auth.message);
      expect(auth.message, contains('Consulta'));
      await auth.login(email, password);
      expect(auth.message, contains('Confirma'));
      // Direct local Auth has /verify rather than gateway /auth/v1/verify.
      final confirmation = Uri.parse(await link());
      await auth.confirm(email, mappedLink(confirmation), recovery: false);
      expect(auth.current, isNotNull, reason: auth.message);
      await auth.login(email, password);
      expect(auth.current, isNotNull, reason: auth.message);
      final identity = auth.current!.namespace;
      auth.dispose();
      auth = make();
      await auth.restore();
      expect(auth.current!.namespace, identity);
      final beforeRotation = vault.values[config.storageKey];
      await auth.renew();
      expect(vault.values[config.storageKey], isNot(beforeRotation));
      // Revoke through a separate SDK client so this adapter still holds the
      // original session and learns revocation through its real renewal path.
      final revoker = GoTrueClient(url: sdkEndpoint, autoRefreshToken: false);
      await revoker.setInitialSession(vault.values[config.storageKey]!);
      await revoker.signOut(scope: SignOutScope.local);
      revoker.dispose();
      vault.deleteFails = true;
      await auth.renew();
      expect(auth.status, SessionStatus.invalidated, reason: auth.message);
      expect(vault.values, isNotEmpty);
      auth.dispose();
      auth = make();
      await auth.restore();
      expect(auth.current, isNull);
      vault.deleteFails = false;
      await auth.restore();
      expect(vault.values, isEmpty);
      await auth.login(email, password);
      await auth.logout();
      expect(vault.values, isEmpty);
      await Future<void>.delayed(const Duration(seconds: 2));
      await auth.recover(email);
      final listing = await mail('messages') as Map;
      expect((listing['messages'] as List).length, greaterThanOrEqualTo(2));
      final recovery = Uri.parse(await link());
      await auth.confirm(email, mappedLink(recovery), recovery: true);
      expect(auth.current, isNotNull, reason: auth.message);
      expect(auth.needsPasswordChange, isTrue);
      auth.dispose();
      auth = make();
      await auth.restore();
      expect(auth.needsPasswordChange, isTrue);
      await auth.changePassword('$password-new');
      expect(auth.needsPasswordChange, isFalse, reason: auth.message);
      await auth.login(email, '$password-new');
      expect(auth.current!.namespace, identity);
      await auth.logout();
      auth.dispose();
    },
    skip: Platform.environment['BATH_REAL_AUTH'] != '1',
  );
}
