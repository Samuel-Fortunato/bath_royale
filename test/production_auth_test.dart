import 'dart:async';
import 'dart:convert';
import 'package:supabase/supabase.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/sync/auth_session.dart';
import 'package:bath_royale/sync/namespace.dart';
import 'package:bath_royale/state/account_state_scope.dart';
import 'package:bath_royale/storage/local_store.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

class MemoryVault implements CredentialVault {
  final values = <String, String>{};
  bool locked = false;
  @override
  Future<String?> read(String key) async {
    if (locked) throw StateError('locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (locked) throw StateError('locked');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (locked) throw StateError('locked');
    values.remove(key);
  }
}

class DelayedVault extends MemoryVault {
  final result = Completer<String?>();
  @override
  Future<String?> read(String key) => result.future;
}

class DelayedLoginClient extends GoTrueClient {
  final response = Completer<AuthResponse>();
  DelayedLoginClient() : super(autoRefreshToken: false);
  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) => response.future;
  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {}
}

Session fixtureSession() => Session(
  accessToken: 'fixture',
  refreshToken: 'fixture-refresh',
  tokenType: 'bearer',
  user: const User(
    id: '11111111-1111-4111-8111-111111111111',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

void main() {
  test(
    'disposed secure restoration cannot reopen identity or renewal timers',
    () async {
      final vault = DelayedVault();
      final auth = ProductionAuth(
        AuthConfiguration('https://one.example', 'client'),
        vault,
      );
      final restore = auth.restore();
      await Future<void>.delayed(Duration.zero);
      auth.dispose();
      vault.result.complete(jsonEncode(fixtureSession().toJson()));
      await restore;
      expect(auth.current, isNull);
    },
  );

  test(
    'superseded login cannot persist or publish after logout intent',
    () async {
      final client = DelayedLoginClient();
      final vault = MemoryVault();
      final auth = ProductionAuth(
        AuthConfiguration('https://one.example', 'client'),
        vault,
        client: client,
      );
      final login = auth.login('fiction@example.invalid', 'password');
      await Future<void>.delayed(Duration.zero);
      final generation = auth.generation;
      final logout = auth.logout();
      expect(auth.generation, greaterThan(generation));
      client.response.complete(AuthResponse(session: fixtureSession()));
      await login;
      expect(auth.current, isNull);
      expect(vault.values, isEmpty);
      await logout;
      auth.dispose();
    },
  );

  test(
    'credential write failure fails closed and environments never share credentials',
    () async {
      final client = DelayedLoginClient();
      final vault = MemoryVault()..locked = true;
      final one = AuthConfiguration('https://one.example', 'client');
      final two = AuthConfiguration('https://two.example', 'client');
      expect(one.storageKey, isNot(two.storageKey));
      final auth = ProductionAuth(one, vault, client: client);
      final login = auth.login('fiction@example.invalid', 'password');
      client.response.complete(AuthResponse(session: fixtureSession()));
      await login;
      expect(auth.current, isNull);
      expect(auth.storageBlocked, isTrue);
      expect(vault.values, isEmpty);
      vault.locked = false;
      vault.values[one.storageKey] = jsonEncode(fixtureSession().toJson());
      final other = ProductionAuth(two, vault);
      await other.restore();
      expect(other.current, isNull);
      await auth.restore();
      expect(auth.current!.namespace.environment, one.environment);
      expect(auth.storageBlocked, isFalse);
      auth.dispose();
      other.dispose();
    },
  );

  test(
    'production configuration rejects insecure and privileged endpoints',
    () {
      expect(
        () => AuthConfiguration('http://127.0.0.1:55471', 'anon'),
        throwsArgumentError,
      );
      expect(
        () => AuthConfiguration('https://example.test', 'sb_secret_x'),
        throwsArgumentError,
      );
      expect(
        () => AuthConfiguration('https://name:pass@example.test', 'anon'),
        throwsArgumentError,
      );
      expect(
        AuthConfiguration(
          'https://example.test/',
          'sb_publishable_x',
        ).environment,
        'https://example.test',
      );
    },
  );

  test(
    'official SDK login, secure restart, offline expiry, rotation, revocation and logout',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var unavailable = false;
      var revoked = false;
      var refreshes = 0;
      final requests = <String>[];
      const subject = '11111111-1111-4111-8111-111111111111';
      final time = DateTime.now().millisecondsSinceEpoch;
      var now = time;
      String jwt() {
        String part(Object v) =>
            base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
        return '${part({'alg': 'HS256'})}.${part({'sub': subject, 'exp': time ~/ 1000 + 3600})}.signature';
      }

      final user = {
        'id': subject,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      };
      server.listen((request) async {
        requests.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        final body = request.method == 'POST'
            ? jsonDecode(await utf8.decoder.bind(request).join()) as Map
            : {};
        if (unavailable) {
          request.response.statusCode = 503;
          request.response.write(jsonEncode({'msg': 'Unavailable'}));
        } else if (request.uri.path.endsWith('/token') &&
            (body['password'] == 'wrong' || revoked)) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({
              'error_code': revoked
                  ? 'refresh_token_not_found'
                  : 'invalid_credentials',
              'msg': 'Rejected',
            }),
          );
        } else if (request.uri.path.endsWith('/logout')) {
          request.response.write('{}');
        } else {
          if (request.uri.queryParameters['grant_type'] == 'refresh_token') {
            refreshes++;
          }
          request.response.write(
            jsonEncode({
              'access_token': jwt(),
              'refresh_token': 'rotated-$refreshes',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': user,
            }),
          );
        }
        await request.response.close();
      });
      final vault = MemoryVault();
      final config = AuthConfiguration(
        'http://127.0.0.1:${server.port}',
        'client',
        localTest: true,
      );
      ProductionAuth make() => ProductionAuth(config, vault, now: () => now);
      var auth = make();
      await auth.restore();
      expect(auth.current, isNull);
      expect(requests, isEmpty);
      await auth.login('fiction@example.invalid', 'wrong');
      expect(auth.message, contains('incorretos'));
      await auth.login('fiction@example.invalid', 'correct');
      expect(
        auth.current!.namespace,
        DataNamespace.account(config.environment, subject),
      );
      expect(vault.values, hasLength(1));
      auth.dispose();
      auth = make();
      unavailable = true;
      requests.clear();
      await auth.restore();
      expect(requests, isEmpty);
      expect(auth.current!.namespace.subject, subject);
      now += 4000000;
      expect(auth.status, SessionStatus.expired);
      final scope = AccountStateScope.forTesting(
        auth: auth,
        offlineAccess: true,
        now: () => now,
        openStore: (n) async =>
            LocalStore(sqlite3.openInMemory(), namespace: n),
      );
      await scope.select(auth.current!.namespace);
      expect(scope.isAccessible, isTrue);
      expect(scope.state!.allBathrooms, isEmpty);
      expect(scope.state!.repository!.syncContext, isNull);
      await auth.renew();
      expect(auth.current, isNotNull);
      expect(scope.isAccessible, isTrue);
      unavailable = false;
      now = time + 3590000;
      await Future.wait([auth.renew(), auth.renew()]);
      expect(refreshes, 1);
      revoked = true;
      await auth.renew();
      expect(auth.current, isNull);
      expect(auth.status, SessionStatus.invalidated);
      expect(scope.isAccessible, isFalse);
      expect(vault.values, isEmpty);
      revoked = false;
      await auth.login('fiction@example.invalid', 'correct');
      await auth.logout();
      expect(auth.current, isNull);
      expect(vault.values, isEmpty);
      expect(requests.every((p) => p.startsWith('/auth/v1/')), isTrue);
      scope.dispose();
      auth.dispose();
      await server.close(force: true);
    },
  );

  test(
    'locked storage neither restores an identity nor falls back to files',
    () async {
      final vault = MemoryVault()..locked = true;
      final auth = ProductionAuth(
        AuthConfiguration('https://example.test', 'client'),
        vault,
      );
      await auth.restore();
      expect(auth.current, isNull);
      expect(auth.storageBlocked, isTrue);
      await auth.login('x@example.invalid', 'password');
      expect(auth.current, isNull);
      vault.locked = false;
      await auth.restore();
      expect(auth.current, isNull);
      auth.dispose();
    },
  );
}
