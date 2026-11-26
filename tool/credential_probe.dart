// Run only against an isolated test Secret Service / device.
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:bath_royale/auth/production_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const vault = PlatformCredentialVault();
  final key = 'bath-royale-probe-${DateTime.now().microsecondsSinceEpoch}';
  try {
    await vault.write(key, 'fictional-probe');
    if (await vault.read(key) != 'fictional-probe') {
      throw StateError('Read mismatch');
    }
    await vault.delete(key);
    if (await vault.read(key) != null) throw StateError('Delete mismatch');
    stdout.writeln('PASS: platform credential write/read/delete');
    exit(0);
  } catch (_) {
    stderr.writeln('FAIL: platform secure storage unavailable');
    exit(1);
  }
}
