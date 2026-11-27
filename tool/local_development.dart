// Deliberately unreachable from lib/main.dart and the distributable alpha target.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bath_royale/auth/production_auth.dart';
import 'package:bath_royale/main.dart';
import 'auth_device_preview.dart' show DevicePreviewTls;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('BATH_ISOLATED_DEVELOPMENT')) {
    throw StateError('Dedicated development configuration required');
  }
  final configuration = AuthConfiguration.localDevelopment(
    const String.fromEnvironment('SUPABASE_URL'),
    const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  final accounts =
      (jsonDecode(
                utf8.decode(
                  base64Decode(
                    const String.fromEnvironment('BATH_LOCAL_TEST_ACCOUNTS'),
                  ),
                ),
              )
              as List)
          .cast<Map<String, dynamic>>();
  HttpOverrides.global = DevicePreviewTls(
    const String.fromEnvironment('BATH_DEVICE_CA_BASE64'),
  );
  runApp(
    AuthenticatedBootstrap(
      createAuth: () =>
          ProductionAuth(configuration, const PlatformCredentialVault()),
      accountEntryExtras: (context) => _TestAccounts(accounts: accounts),
    ),
  );
}

Widget developmentAccounts(List<Map<String, dynamic>> accounts) =>
    _TestAccounts(accounts: accounts);

class _TestAccounts extends StatelessWidget {
  final List<Map<String, dynamic>> accounts;
  const _TestAccounts({required this.accounts});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProductionAuth>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Contas de teste · só desenvolvimento\nDados fictícios, sem ligação à alfa distribuível.',
        ),
        for (final account in accounts)
          OutlinedButton(
            onPressed: auth.busy
                ? null
                : () => auth.login(
                    account['email'] as String,
                    account['password'] as String,
                  ),
            child: Text(account['email'] as String),
          ),
      ],
    );
  }
}
