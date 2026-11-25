import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'local_store.dart';

Future<LocalStore> openLocalStore() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return LocalStore(
    sqlite3.open(
      '${directory.path}${Platform.pathSeparator}bath_royale.sqlite',
    ),
  );
}
