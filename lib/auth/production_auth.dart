import 'alpha_policy.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase/supabase.dart';
import '../sync/auth_session.dart';
import '../sync/namespace.dart';
import 'restoration_guard.dart';

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
  // Presentation/capability policy only. The server decides confirmation.
  final bool emailConfirmationRequired;
  final bool passwordRecoveryAvailable;
  AuthConfiguration(String url, this.clientKey, {bool localTest = false})
    : emailConfirmationRequired = true,
      passwordRecoveryAvailable = true,
      endpoint = Uri.parse(url) {
    _validate(localTest);
  }

  /// Public alpha policy; unverified email is an account label, never recovery proof.
  AuthConfiguration.alpha(String url, this.clientKey)
    : emailConfirmationRequired = false,
      passwordRecoveryAvailable = false,
      endpoint = Uri.parse(url) {
    _validate(false);
  }

  /// No ordinary dart-define can enable local alpha policy for a managed host.
  AuthConfiguration.localAlpha(String url, this.clientKey)
    : emailConfirmationRequired = false,
      passwordRecoveryAvailable = false,
      endpoint = Uri.parse(url) {
    if (url != 'https://localhost:55474' ||
        clientKey != 'local-device-client') {
      throw ArgumentError('Isolated USB alpha endpoint required');
    }
    _validate(false);
  }

  /// Dedicated non-distributable development target; never accepts a managed host.
  AuthConfiguration.localDevelopment(String url, this.clientKey)
    : emailConfirmationRequired = false,
      passwordRecoveryAvailable = false,
      endpoint = Uri.parse(url) {
    if (url != 'https://localhost:55504' ||
        clientKey != 'local-development-client') {
      throw ArgumentError('Isolated development endpoint required');
    }
    _validate(false);
  }

  void _validate(bool localTest) {
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

/// Official Auth SDK with secure persistence; remote data uses a separate adapter.
/// Operations are serialized, including refresh rotation and credential writes.
class ProductionAuth extends ChangeNotifier implements AuthSession {
  final AuthConfiguration configuration;
  final CredentialVault vault;
  final RestorationGuard restorationGuard;
  String? privateEmail;
  bool needsPasswordChange = false;
  final GoTrueClient client;
  final int Function() now;
  ProductionAuth(
    this.configuration,
    this.vault, {
    this.restorationGuard = const PlatformRestorationGuard(),
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
  void clearMessage() {
    message = null;
    notifyListeners();
  }

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
    privateEmail = session.user.email;
    _identity = SessionIdentity(
      DataNamespace.account(configuration.environment, session.user.id),
      (session.expiresAt ?? 0) * 1000,
    );
    _status = SessionStatus.authenticated;
    _generation++;
    notifyListeners();
  }

  void _forget(SessionStatus status) {
    _identity = null;
    privateEmail = null;
    needsPasswordChange = false;
    _status = status;
    _generation++;
  }

  Future<void> _setRestoration(bool allowed) =>
      restorationGuard.setAllowed(configuration.environment, allowed);

  Future<void> _persist(Session session, {bool? recovery}) async {
    if (_disposed || _active != _scheduled) return;
    try {
      await _setRestoration(false);
      if (_disposed || _active != _scheduled) return;
      final changingPassword = recovery ?? needsPasswordChange;
      await vault.write(
        configuration.storageKey,
        jsonEncode({
          ...session.toJson(),
          'bath_password_recovery': changingPassword,
        }),
      );
      if (_disposed || _active != _scheduled) return;
      await _setRestoration(true);
      needsPasswordChange = changingPassword;
      storageBlocked = false;
    } catch (_) {
      storageBlocked = true;
      // The guard remains denied even if secure storage cannot be changed.
      try {
        await vault.delete(configuration.storageKey);
      } catch (_) {}
      _forget(SessionStatus.invalidated);
      rethrow;
    }
  }

  Future<void> restore() => _run(() async {
    try {
      final allowed = await restorationGuard.isAllowed(
        configuration.environment,
      );
      if (_disposed || _active != _scheduled) return;
      if (!allowed) {
        _forget(SessionStatus.invalidated);
        await vault.delete(configuration.storageKey);
        storageBlocked = false;
        message = 'Entra novamente na conta para continuar.';
        return;
      }
      final stored = await vault.read(configuration.storageKey);
      if (_disposed || _active != _scheduled) return;
      storageBlocked = false;
      if (stored == null) {
        _forget(SessionStatus.unauthenticated);
      } else {
        await client.setInitialSession(
          stored,
        ); // No network, even for expired JWTs.
        final session = client.currentSession;
        if (session == null) throw StateError('Missing session');
        needsPasswordChange =
            (jsonDecode(stored) as Map)['bath_password_recovery'] == true;
        _publish(session);
      }
    } catch (_) {
      storageBlocked = true;
      _forget(SessionStatus.invalidated);
      rethrow;
    } finally {
      if (!_disposed) {
        _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
          renew();
        });
      }
    }
  });

  Future<void> login(String email, String password) => _run(() async {
    if (storageBlocked) throw StateError('Unlock credential storage first');
    final response = await client.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _persist(response.session!, recovery: false);
    _publish(response.session!);
  });

  Future<void> register(String email, String password) => _run(() async {
    if (storageBlocked) throw StateError('Unlock credential storage first');
    final response = await client.signUp(
      email: email.trim(),
      password: password,
    );
    if (response.session != null) {
      await _persist(response.session!, recovery: false);
      _publish(response.session!);
    } else {
      message =
          'Consulta o teu email para confirmar a conta. Os teus dados continuam apenas neste dispositivo.';
    }
  });

  Future<void> recover(String email) => _run(() async {
    if (!configuration.passwordRecoveryAvailable) {
      message = alphaRecoveryInformation;
      return;
    }
    await client.resetPasswordForEmail(email.trim());
    message =
        'Se o endereço tiver uma conta, receberás instruções. Podes introduzir o código do email aqui.';
  });

  Future<void> confirm(String email, String code, {required bool recovery}) =>
      _run(() async {
        if (storageBlocked) throw StateError('Unlock credential storage first');
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
        await _persist(response.session!, recovery: recovery);
        _publish(response.session!);
      });

  Future<void> changePassword(String password, {String? currentPassword}) =>
      _run(() async {
        if (storageBlocked || status != SessionStatus.authenticated) {
          throw StateError('Reauthenticate first');
        }
        await client.updateUser(
          UserAttributes(password: password, currentPassword: currentPassword),
        );
        if (client.currentSession != null) {
          await _persist(client.currentSession!, recovery: false);
        }
        message = 'Palavra-passe atualizada.';
      });

  Future<String?> createRecoveryCode(String currentPassword) async {
    String? code;
    await _run(() async {
      if (current == null || privateEmail == null || storageBlocked) {
        throw StateError('Sign in first');
      }
      final temporary = SupabaseClient(
        configuration.environment,
        configuration.clientKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        final response = await temporary.auth.signInWithPassword(
          email: privateEmail!,
          password: currentPassword,
        );
        if (response.user?.id != current!.namespace.subject) {
          throw StateError('Account mismatch');
        }
        code = await temporary.rpc('create_alpha_recovery_code') as String;
      } finally {
        try {
          await temporary.auth.signOut(scope: SignOutScope.local);
        } finally {
          await temporary.dispose();
        }
      }
    });
    return code;
  }

  Future<void>? _renewing;
  Future<void> renew({bool force = false}) {
    return _renewing ??= _renew(
      force: force,
    ).whenComplete(() => _renewing = null);
  }

  Future<void> _renew({bool force = false}) {
    if (_disposed ||
        storageBlocked ||
        busy ||
        _identity == null ||
        !force && _identity!.expiresAt > now() + 30000) {
      return Future.value();
    }
    return _run(() async {
      if (_identity == null) return;
      if (!force && _identity!.expiresAt > now() + 30000) return;
      // Commit denial before a network call can rotate/revoke the secure token.
      try {
        await _setRestoration(false);
      } catch (_) {
        storageBlocked = true;
        rethrow; // No request: cannot learn revocation without durable denial.
      }
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
      } catch (error) {
        if (error is AuthException &&
            {
              'refresh_token_not_found',
              'refresh_token_already_used',
              'session_not_found',
              'session_expired',
              'bad_jwt',
              'user_banned',
              'user_not_found',
            }.contains(error.code)) {
          _forget(SessionStatus.invalidated);
          try {
            await vault.delete(configuration.storageKey);
          } catch (_) {
            storageBlocked = true;
            rethrow;
          }
        } else if (_identity != null &&
            !storageBlocked &&
            !_disposed &&
            _active == _scheduled) {
          // Transient network failure preserves restartable offline access.
          try {
            await _setRestoration(true);
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
    // Denial must commit first. A failed deletion remains a failed logout,
    // but can no longer restore credentials after process death.
    try {
      await _setRestoration(false);
      await vault.delete(configuration.storageKey);
      storageBlocked = false;
    } catch (_) {
      storageBlocked = true;
      rethrow;
    }
    _forget(SessionStatus.unauthenticated);
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
