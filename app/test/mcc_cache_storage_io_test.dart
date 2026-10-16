@TestOn('vm')
library;

import 'dart:io';
import 'package:cashflow/services/mcc_cache_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cashflow-mcc-storage-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('flushed generations survive reopening and remain key scoped', () async {
    final storage = FileMccStorage(directory: () async => root);
    await storage.write('account:1:date', 'one');
    await storage.write('account:2:date', 'two');
    await storage.write('account:1:date', 'new one');
    final reopened = FileMccStorage(directory: () async => root);
    expect(await reopened.read('account:1:date'), 'new one');
    expect(await reopened.read('account:2:date'), 'two');
    expect(await reopened.keys(), {'account:1:date', 'account:2:date'});
    await reopened.remove('account:1:date');
    expect(await reopened.read('account:1:date'), isNull);
    expect(await reopened.read('account:2:date'), 'two');
  });

  test('failed commit preserves the previous generation after restart',
      () async {
    final storage = FileMccStorage(directory: () async => root);
    await storage.write('synthetic-key', 'last valid');
    final failed = FileMccStorage(
        directory: () async => root,
        commitFile: (_, __) async {
          throw const FileSystemException('Synthetic disk full');
        });
    await expectLater(failed.write('synthetic-key', 'incomplete replacement'),
        throwsA(isA<FileSystemException>()));
    expect(
        await FileMccStorage(directory: () async => root).read('synthetic-key'),
        'last valid');
    expect(
        await root
            .list(recursive: true)
            .where((file) => file.path.endsWith('.tmp'))
            .length,
        0);
  });

  test('corrupted latest generation falls back to prior valid file', () async {
    final storage = FileMccStorage(directory: () async => root);
    await storage.write('synthetic-key', 'first');
    await storage.write('synthetic-key', 'second');
    final files = await root
        .list(recursive: true)
        .where((item) => item is File && item.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    for (final corrupt in ['corrupt', '[]', 'null']) {
      await files.first.writeAsString(corrupt);
      final reopened = FileMccStorage(directory: () async => root);
      expect(await reopened.read('synthetic-key'), 'first');
      expect(await reopened.keys(), {'synthetic-key'});
    }
  });
}
