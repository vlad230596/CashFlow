import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'mcc_cache_storage.dart';

MccStorage createStorage() => FileMccStorage();

/// Immutable generations avoid replacing the only valid file on Windows.
/// A new generation becomes visible only after its flushed temporary file is
/// renamed to a unique final name. Old generations survive failed writes.
class FileMccStorage implements MccStorage {
  FileMccStorage(
      {Future<Directory> Function()? directory,
      Future<void> Function(File temporary, String target)? commitFile})
      : _directory = directory ?? _defaultDirectory,
        _commitFile = commitFile ?? _rename;
  final Future<Directory> Function() _directory;
  final Future<void> Function(File temporary, String target) _commitFile;
  static final _random = Random.secure();
  Future<Directory>? _root;

  static Future<void> _rename(File temporary, String target) async {
    await temporary.rename(target);
  }

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}mcc-cache-v2');
  }

  Future<Directory> _records(String key) async {
    final root = await (_root ??= _directory());
    return Directory('${root.path}${Platform.pathSeparator}'
        '${sha256.convert(utf8.encode(key))}');
  }

  Future<List<File>> _generations(Directory directory) async {
    if (!await directory.exists()) return [];
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  @override
  Future<String?> read(String key) async {
    for (final file in await _generations(await _records(key))) {
      try {
        final record = jsonDecode(await file.readAsString());
        if (record is Map &&
            record['key'] == key &&
            record['value'] is String) {
          return record['value'] as String;
        }
      } on FormatException {
        // An incomplete/corrupt generation must not hide a preceding one.
      } on FileSystemException {
        // Another cache writer can retire a generation during this read.
      }
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    final directory = await _records(key);
    await directory.create(recursive: true);
    final previous = await _generations(directory);
    final last = previous.isEmpty
        ? 0
        : int.tryParse(previous.first.uri.pathSegments.last.split('-').first) ??
            0;
    final stamp = max(DateTime.now().microsecondsSinceEpoch, last + 1);
    final filename = '${stamp.toString().padLeft(20, '0')}-'
        '${_random.nextInt(1 << 32)}';
    final temporary =
        File('${directory.path}${Platform.pathSeparator}$filename.tmp');
    final committed =
        '${directory.path}${Platform.pathSeparator}$filename.json';
    try {
      await temporary.writeAsString(jsonEncode({'key': key, 'value': value}),
          flush: true);
      await _commitFile(temporary, committed);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    // Keep one preceding generation as corruption recovery. Cleanup is best
    // effort and occurs only after the new generation is durably written.
    for (final obsolete in previous.skip(1)) {
      try {
        await obsolete.delete();
      } on FileSystemException {/* retry later */}
    }
  }

  @override
  Future<void> remove(String key) async {
    for (final file in await _generations(await _records(key))) {
      try {
        await file.delete();
      } on FileSystemException {/* already removed */}
    }
  }

  @override
  Future<Set<String>> keys() async {
    final root = await (_root ??= _directory());
    if (!await root.exists()) return {};
    final result = <String>{};
    await for (final directory in root.list()) {
      if (directory is! Directory) continue;
      for (final file in await _generations(directory)) {
        try {
          final record = jsonDecode(await file.readAsString());
          if (record is Map && record['key'] is String) {
            result.add(record['key'] as String);
            break;
          }
        } on FormatException {
          /* inspect previous generation */
        } on FileSystemException {/* concurrent retirement */}
      }
    }
    return result;
  }
}
