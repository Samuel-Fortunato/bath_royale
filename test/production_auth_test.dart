import 'dart:async';
import 'package:bath_royale/auth/restoration_guard.dart';
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

class MemoryGuard implements RestorationGuard {
  final values = <String, bool>{};
  bool locked = false;
  @override
  Future<bool> isAllowed(String environment) async {
    if (locked) throw StateError('guard locked');
    return values[environment] ?? false;
  }

  @override
  Future<void> setAllowed(String environment, bool allowed) async {
    if (locked) throw StateError('guard locked');
    values[environment] = allowed;
  }
}

class MemoryVault implements CredentialVault {
  final guard = MemoryGuard();
  final values = <String, String>{};
  bool locked = false;
  bool deleteFails = false;
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
    if (locked || deleteFails) throw StateError('locked');
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
    email: 'fiction@example.invalid',
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class TransientClient extends DelayedLoginClient {
  int refreshes = 0;
  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async {
    refreshes++;
    throw const AuthException('Unavailable', statusCode: '503');
  }
}

class RevokedClient extends DelayedLoginClient {
  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async =>
      throw const AuthException('Revoked', code: 'session_not_found');
}

void main() {
  test(
    'failed logout denies restart restoration until explicit authentication',
    () async {
      final vault = MemoryVault();
      final config = AuthConfiguration('https://logout.example', 'client');
      final client = DelayedLoginClient();
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      client.response.complete(AuthResponse(session: fixtureSession()));
      await auth.login('fiction@example.invalid', 'password');
      final original = auth.current;
      vault.deleteFails = true;
      await auth.logout();
      expect(auth.current, same(original));
      expect(auth.storageBlocked, isTrue);
      expect(auth.message, isNotNull);
      final failure = auth.message;
      final generation = auth.generation;
      await auth.renew();
      expect(auth.message, failure);
      expect(auth.generation, generation);
      expect(await vault.guard.isAllowed(config.environment), isFalse);
      auth.dispose();
      final restarted = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: DelayedLoginClient(),
      );
      await restarted.restore();
      expect(restarted.current, isNull);
      vault.deleteFails = false;
      await restarted.restore();
      expect(restarted.storageBlocked, isFalse);
      expect(restarted.current, isNull);
      restarted.dispose();
    },
  );

  test(
    'guard failure prevents renewal requests and fails closed on restoration',
    () async {
      final vault = MemoryVault();
      final config = AuthConfiguration('https://guard.example', 'client');
      final client = TransientClient();
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      client.response.complete(AuthResponse(session: fixtureSession()));
      await auth.login('fiction@example.invalid', 'password');
      vault.guard.locked = true;
      await auth.renew();
      expect(client.refreshes, 0);
      expect(auth.storageBlocked, isTrue);
      expect(auth.current, isNotNull);
      await auth.restore();
      expect(auth.current, isNull);
      expect(vault.values, isNotEmpty);
      vault.guard.locked = false;
      await auth.restore();
      expect(auth.current, isNotNull);
      auth.dispose();
    },
  );

  test(
    'transient renewal failure keeps offline credentials restartable',
    () async {
      final vault = MemoryVault();
      final config = AuthConfiguration('https://offline.example', 'client');
      final client = TransientClient();
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      client.response.complete(AuthResponse(session: fixtureSession()));
      await auth.login('fiction@example.invalid', 'password');
      await auth.renew();
      expect(client.refreshes, 1);
      expect(auth.current, isNotNull);
      expect(await vault.guard.isAllowed(config.environment), isTrue);
      auth.dispose();
      final restarted = ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
      );
      await restarted.restore();
      expect(restarted.current, isNotNull);
      restarted.dispose();
    },
  );

  test(
    'revocation with failed deletion cannot restore after restart',
    () async {
      final vault = MemoryVault();
      final config = AuthConfiguration('https://revoked.example', 'client');
      final directory = Directory.systemTemp.createTempSync('bath-auth-guard-');
      addTearDown(() => directory.deleteSync(recursive: true));
      PlatformRestorationGuard guard() =>
          PlatformRestorationGuard(directory: () async => directory);
      final client = RevokedClient();
      final auth = ProductionAuth(
        config,
        vault,
        restorationGuard: guard(),
        client: client,
      );
      client.response.complete(AuthResponse(session: fixtureSession()));
      await auth.login('fiction@example.invalid', 'password');
      vault.deleteFails = true;
      await auth.renew();
      expect(auth.status, SessionStatus.invalidated);
      expect(vault.values, isNotEmpty);
      auth.dispose();
      final restarted = ProductionAuth(
        config,
        vault,
        restorationGuard: guard(),
      );
      await restarted.restore();
      expect(restarted.current, isNull);
      expect(restarted.storageBlocked, isTrue);
      vault.deleteFails = false;
      await restarted.restore();
      expect(restarted.current, isNull);
      expect(vault.values, isEmpty);
      await restarted.restore();
      expect(restarted.current, isNull);
      final bytes = File(
        '${directory.path}/auth-restoration.sqlite3',
      ).readAsBytesSync();
      expect(latin1.decode(bytes), isNot(contains('fixture-refresh')));
      restarted.dispose();
      vault.values[config.storageKey] = jsonEncode(fixtureSession().toJson());
      File('${directory.path}/auth-restoration.sqlite3').deleteSync();
      final missingGuard = ProductionAuth(
        config,
        vault,
        restorationGuard: guard(),
      );
      await missingGuard.restore();
      expect(missingGuard.current, isNull);
      expect(vault.values, isEmpty);
      missingGuard.dispose();
      vault.values[config.storageKey] = jsonEncode(fixtureSession().toJson());
      final database = sqlite3.open(
        '${directory.path}/auth-restoration.sqlite3',
      );
      database.userVersion = 99;
      database.close();
      final unknownGuard = ProductionAuth(
        config,
        vault,
        restorationGuard: guard(),
      );
      await unknownGuard.restore();
      expect(unknownGuard.current, isNull);
      expect(unknownGuard.storageBlocked, isTrue);
      expect(vault.values, isNotEmpty);
      unknownGuard.dispose();
    },
  );

  test(
    'renewal before expiry preserves messages, generation and listeners',
    () async {
      final client = DelayedLoginClient();
      final auth = ProductionAuth(
        AuthConfiguration('https://valid.example', 'client'),
        MemoryVault(),
        restorationGuard: MemoryGuard(),
        client: client,
      );
      final session = fixtureSession()
        ..expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      client.response.complete(AuthResponse(session: session));
      await auth.login('fiction@example.invalid', 'password');
      auth.message = 'Mensagem a preservar';
      final generation = auth.generation;
      var notifications = 0;
      auth.addListener(() => notifications++);
      await auth.renew();
      expect(auth.message, 'Mensagem a preservar');
      expect(auth.generation, generation);
      expect(notifications, 0);
      expect(auth.busy, isFalse);
      auth.dispose();
    },
  );

  test(
    'disposed secure restoration cannot reopen identity or renewal timers',
    () async {
      final vault = DelayedVault();
      vault.guard.values['https://one.example'] = true;
      final auth = ProductionAuth(
        AuthConfiguration('https://one.example', 'client'),
        vault,
        restorationGuard: vault.guard,
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
        restorationGuard: vault.guard,
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
      final auth = ProductionAuth(
        one,
        vault,
        restorationGuard: vault.guard,
        client: client,
      );
      final login = auth.login('fiction@example.invalid', 'password');
      client.response.complete(AuthResponse(session: fixtureSession()));
      await login;
      expect(auth.current, isNull);
      expect(auth.storageBlocked, isTrue);
      expect(vault.values, isEmpty);
      vault.locked = false;
      vault.values[one.storageKey] = jsonEncode(fixtureSession().toJson());
      final other = ProductionAuth(two, vault, restorationGuard: vault.guard);
      await other.restore();
      expect(other.current, isNull);
      await auth.restore();
      expect(auth.current, isNull);
      await auth.login('fiction@example.invalid', 'password');
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
      ProductionAuth make() => ProductionAuth(
        config,
        vault,
        restorationGuard: vault.guard,
        now: () => now,
      );
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
        restorationGuard: vault.guard,
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
