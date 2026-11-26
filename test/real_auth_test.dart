import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'production_auth_test.dart' show MemoryVault;

void main() {
  test(
    'isolated real registration, confirmation, recovery, rotation and logout',
    () async {
      final vault = MemoryVault();
      final config = AuthConfiguration(
        'http://127.0.0.1:55471',
        'local-client',
        localTest: true,
      );
      ProductionAuth make() => ProductionAuth(
        config,
        vault,
        now: () => DateTime.now().millisecondsSinceEpoch + 45000,
        client: GoTrueClient(
          url: config.environment,
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
      await auth.confirm(
        email,
        confirmation.replace(path: '/auth/v1/verify').toString(),
        recovery: false,
      );
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
      await auth.login(email, password);
      await auth.logout();
      expect(vault.values, isEmpty);
      await Future<void>.delayed(const Duration(seconds: 2));
      await auth.recover(email);
      final listing = await mail('messages') as Map;
      expect((listing['messages'] as List).length, greaterThanOrEqualTo(2));
      final recovery = Uri.parse(await link());
      await auth.confirm(
        email,
        recovery.replace(path: '/auth/v1/verify').toString(),
        recovery: true,
      );
      expect(auth.current, isNotNull, reason: auth.message);
      await auth.changePassword('$password-new');
      await auth.login(email, '$password-new');
      expect(auth.current!.namespace, identity);
      await auth.logout();
      auth.dispose();
    },
    skip: Platform.environment['BATH_REAL_AUTH'] != '1',
  );
}
