import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'local_store.dart';
import '../sync/namespace.dart';

Future<LocalStore> openLocalStore({
  DataNamespace namespace = const DataNamespace.guest(),
}) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return LocalStore(
    sqlite3.open(
      '${directory.path}${Platform.pathSeparator}${namespace.fileName}',
    ),
    namespace: namespace,
  );
}
