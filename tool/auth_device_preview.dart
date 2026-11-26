// Local device testing only. The ordinary lib/main.dart target never imports
// this file and never accepts a custom certificate authority.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/main.dart';

class DevicePreviewTls extends HttpOverrides {
  final SecurityContext trusted;
  DevicePreviewTls(String certificate)
    : trusted = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(certificate));

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(trusted)..findProxy = (_) => 'DIRECT';
}

AuthConfiguration devicePreviewConfiguration(String endpoint, String key) {
  if (endpoint != 'https://localhost:55474' || key != 'local-device-client') {
    throw ArgumentError('Only the isolated USB development backend is allowed');
  }
  return AuthConfiguration(
    endpoint,
    key,
  ); // Release HTTPS validation unchanged.
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = devicePreviewConfiguration(
    const String.fromEnvironment('SUPABASE_URL'),
    const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  HttpOverrides.global = DevicePreviewTls(
    const String.fromEnvironment('BATH_DEVICE_CA_BASE64'),
  );
  runApp(
    AuthenticatedBootstrap(
      createAuth: () =>
          ProductionAuth(configuration, const PlatformCredentialVault()),
    ),
  );
}
