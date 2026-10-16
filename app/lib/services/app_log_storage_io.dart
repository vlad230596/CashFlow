import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

AppLogStorage? createAppLogStorage() => FileAppLogStorage();

/// Appends to `cashflow.log`, keeping one rotated `cashflow.log.1`.
///
/// On Android the file lives in the app-specific external directory
/// (`/sdcard/Android/data/<package>/files/logs`) so `adb pull` can read it
/// from a release build, which `run-as` cannot.
class FileAppLogStorage implements AppLogStorage {
  FileAppLogStorage({
    Future<Directory> Function()? directory,
    this.maxBytes = 256 * 1024,
  }) : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;
  final int maxBytes;
  Future<File>? _file;

  static Future<Directory> _defaultDirectory() async {
    Directory? base;
    if (Platform.isAndroid) base = await getExternalStorageDirectory();
    base ??= await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}logs');
  }

  Future<File> _open() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}cashflow.log');
  }

  @override
  Future<void> append(String lines) async {
    final file = await (_file ??= _open());
    if (await file.exists() && await file.length() > maxBytes) {
      await file.rename('${file.path}.1');
    }
    await file.writeAsString(lines, mode: FileMode.append, flush: true);
  }
}
