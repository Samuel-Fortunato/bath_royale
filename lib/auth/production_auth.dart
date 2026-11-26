import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase/supabase.dart';
import '../sync/auth_session.dart';
import '../sync/namespace.dart';

abstract interface class CredentialVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformCredentialVault implements CredentialVault {
  final FlutterSecureStorage storage;
  const PlatformCredentialVault([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false),
    ),
  ]);
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class AuthConfiguration {
  final Uri endpoint;
  final String clientKey;
  AuthConfiguration(String url, this.clientKey, {bool localTest = false})
    : endpoint = Uri.parse(url) {
    if (endpoint.userInfo.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        endpoint.host.isEmpty ||
        (endpoint.scheme != 'https' &&
            !(localTest &&
                !kReleaseMode &&
                endpoint.scheme == 'http' &&
                endpoint.host == '127.0.0.1'))) {
      throw ArgumentError('HTTPS backend required');
    }
    if (clientKey.isEmpty || clientKey.startsWith('sb_secret_')) {
      throw ArgumentError('Publishable client key required');
    }
    if (clientKey.split('.').length == 3) {
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(clientKey.split('.')[1]),
                  ),
                ),
              )
              as Map;
      if (payload['role'] != 'anon') {
        throw ArgumentError('Anonymous client key required');
      }
    }
  }
  String get environment => endpoint.toString().replaceAll(RegExp(r'/$'), '');
  String get storageKey => 'bath-auth:${Uri.encodeComponent(environment)}';
}

/// Official Auth SDK only; no database, realtime, profile or sync client exists.
/// Operations are serialized, including refresh rotation and credential writes.
class ProductionAuth extends ChangeNotifier implements AuthSession {
  final AuthConfiguration configuration;
  final CredentialVault vault;
  final GoTrueClient client;
  final int Function() now;
  ProductionAuth(
    this.configuration,
    this.vault, {
    GoTrueClient? client,
    int Function()? now,
  }) : client =
           client ??
           GoTrueClient(
             url: '${configuration.environment}/auth/v1',
             headers: {'apikey': configuration.clientKey},
             flowType: AuthFlowType.implicit,
             autoRefreshToken: false,
           ),
       now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  SessionIdentity? _identity;
  @override
  SessionIdentity? get current => _identity;
  int _generation = 0;
  @override
  int get generation => _generation;
  SessionStatus _status = SessionStatus.unauthenticated;
  @override
  SessionStatus get status => _identity != null && _identity!.expiresAt <= now()
      ? SessionStatus.expired
      : _status;
  bool busy = false;
  bool storageBlocked = false;
  String? message;
  bool _disposed = false;
  Timer? _timer;
  Future<void> _tail = Future.value();
  int _scheduled = 0;
  int _active = 0;

  Future<void> _run(Future<void> Function() action) {
    final ticket = ++_scheduled;
    _generation++;
    final result = _tail.then((_) async {
      if (_disposed) return;
      _active = ticket;
      busy = true;
      message = null;
      notifyListeners();
      try {
        await action();
      } catch (error) {
        message = error is AuthException
            ? (error.code == 'invalid_credentials'
                  ? 'Email ou palavra-passe incorretos.'
                  : error.code == 'email_not_confirmed'
                  ? 'Confirma o teu email antes de entrar.'
                  : 'Não foi possível autenticar. Verifica os dados e tenta novamente.')
            : 'Serviço ou armazenamento seguro indisponível. Tenta novamente.';
      } finally {
        busy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  void _publish(Session session) {
    if (_disposed || _active != _scheduled) return;
    _identity = SessionIdentity(
      DataNamespace.account(configuration.environment, session.user.id),
      (session.expiresAt ?? 0) * 1000,
    );
    _status = SessionStatus.authenticated;
    _generation++;
    notifyListeners();
  }

  Future<void> _persist(Session session) async {
    if (_disposed || _active != _scheduled) return;
    try {
      await vault.write(configuration.storageKey, jsonEncode(session.toJson()));
      storageBlocked = false;
    } catch (_) {
      storageBlocked = true;
      // A rotated token must not leave an older reusable token on disk.
      try {
        await vault.delete(configuration.storageKey);
      } catch (_) {}
      _identity = null;
      _status = SessionStatus.invalidated;
      _generation++;
      rethrow;
    }
  }

  Future<void> restore() => _run(() async {
    String? stored;
    try {
      stored = await vault.read(configuration.storageKey);
      storageBlocked = false;
    } catch (_) {
      storageBlocked = true;
      rethrow;
    }
    if (_disposed || _active != _scheduled) return;
    if (stored == null) {
      _identity = null;
      _status = SessionStatus.unauthenticated;
      _generation++;
    }
    if (stored != null) {
      await client.setInitialSession(
        stored,
      ); // No network, even for expired JWTs.
      final session = client.currentSession;
      if (session == null) throw StateError('Missing session');
      _publish(session);
    }
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      renew();
    });
  });

  Future<void> login(String email, String password) => _run(() async {
    if (storageBlocked) throw StateError('Unlock credential storage first');
    final response = await client.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _persist(response.session!);
    _publish(response.session!);
  });

  Future<void> register(String email, String password) => _run(() async {
    if (storageBlocked) throw StateError('Unlock credential storage first');
    final response = await client.signUp(
      email: email.trim(),
      password: password,
    );
    if (response.session != null) {
      await _persist(response.session!);
      _publish(response.session!);
    } else {
      message =
          'Consulta o teu email para confirmar a conta. Os teus dados continuam apenas neste dispositivo.';
    }
  });

  Future<void> recover(String email) => _run(() async {
    await client.resetPasswordForEmail(email.trim());
    message =
        'Se o endereço tiver uma conta, receberás instruções. Podes introduzir o código do email aqui.';
  });

  Future<void> confirm(String email, String code, {required bool recovery}) =>
      _run(() async {
        final link = Uri.tryParse(code.trim());
        final hash = link?.queryParameters['token'];
        if (hash != null &&
            (link!.host != configuration.endpoint.host ||
                link.scheme != configuration.endpoint.scheme ||
                link.port != configuration.endpoint.port ||
                link.path !=
                    '${configuration.endpoint.path}/auth/v1/verify'.replaceAll(
                      '//',
                      '/',
                    ))) {
          throw ArgumentError('Invalid confirmation origin');
        }
        final response = await client.verifyOTP(
          email: hash == null ? email.trim() : null,
          token: hash == null ? code.trim() : null,
          tokenHash: hash,
          type: recovery ? OtpType.recovery : OtpType.signup,
        );
        await _persist(response.session!);
        _publish(response.session!);
      });

  Future<void> changePassword(String password) => _run(() async {
    if (status != SessionStatus.authenticated) {
      throw StateError('Reauthenticate first');
    }
    await client.updateUser(UserAttributes(password: password));
    if (client.currentSession != null) await _persist(client.currentSession!);
    message = 'Palavra-passe atualizada.';
  });

  Future<void>? _renewing;
  Future<void> renew() {
    return _renewing ??= _renew().whenComplete(() => _renewing = null);
  }

  Future<void> _renew() {
    if (busy || _identity == null) return Future.value();
    return _run(() async {
      if (_identity == null) return;
      if (_identity!.expiresAt > now() + 30000) return;
      _generation++; // Expiry invalidates pending remote results before await.
      notifyListeners();
      try {
        final previous = _identity!.namespace;
        final response = await client.refreshSession();
        if (response.session == null ||
            response.session!.user.id != previous.subject) {
          throw const AuthException(
            'Invalid refresh identity',
            code: 'session_not_found',
          );
        }
        await _persist(response.session!);
        _publish(response.session!);
      } on AuthException catch (error) {
        if ({
          'refresh_token_not_found',
          'refresh_token_already_used',
          'session_not_found',
          'session_expired',
          'bad_jwt',
          'user_banned',
          'user_not_found',
        }.contains(error.code)) {
          _identity = null;
          _status = SessionStatus.invalidated;
          _generation++;
          try {
            await vault.delete(configuration.storageKey);
          } catch (_) {
            storageBlocked = true;
            rethrow;
          }
        }
        rethrow;
      }
    });
  }

  Future<void> logout() => _run(() async {
    // Delete must succeed before reporting logout; no plaintext fallback.
    await vault.delete(configuration.storageKey);
    _identity = null;
    _status = SessionStatus.unauthenticated;
    _generation++;
    notifyListeners();
    // Local credentials are already removed; unavailable server cannot block guest return.
    try {
      await client
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    client.dispose();
    super.dispose();
  }
}
