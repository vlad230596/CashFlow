import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'mcc_cache_storage.dart';

MccStorage createStorage() => IndexedDbMccStorage();

/// IndexedDB commits a replacement atomically, including quota failures.
class IndexedDbMccStorage implements MccStorage {
  IndexedDbMccStorage(
      {this.databaseName = 'cashflow-mcc-v2', this.beforeCommit});
  final String databaseName;
  final void Function(web.IDBTransaction)? beforeCommit;
  Future<web.IDBDatabase>? _database;
  static const _store = 'records';

  Future<web.IDBDatabase> _open() => _database ??= () {
        final completer = Completer<web.IDBDatabase>();
        final request = web.window.indexedDB.open(databaseName, 1);
        request.onupgradeneeded = ((web.Event _) {
          final database = request.result as web.IDBDatabase;
          database.createObjectStore(_store);
        }).toJS;
        request.onsuccess = ((web.Event _) {
          final database = request.result as web.IDBDatabase;
          database.onversionchange = ((web.Event _) {
            database.close();
            _database = null;
          }).toJS;
          completer.complete(database);
        }).toJS;
        request.onerror = ((web.Event _) {
          _database = null;
          completer.completeError(StateError('Cannot open MCC IndexedDB'));
        }).toJS;
        return completer.future;
      }();

  Future<JSAny?> _request(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('MCC IndexedDB request failed'));
    }).toJS;
    return completer.future;
  }

  Future<void> _change(
      void Function(web.IDBObjectStore store) operation) async {
    final database = await _open();
    final transaction = database.transaction(_store.toJS, 'readwrite');
    final completer = Completer<void>();
    void failed(web.Event _) {
      if (!completer.isCompleted) {
        completer
            .completeError(StateError('MCC IndexedDB transaction aborted'));
      }
    }

    transaction.oncomplete = ((web.Event _) {
      completer.complete();
    }).toJS;
    transaction.onabort = failed.toJS;
    transaction.onerror = failed.toJS;
    operation(transaction.objectStore(_store));
    beforeCommit?.call(transaction);
    await completer.future;
  }

  @override
  Future<String?> read(String key) async {
    final database = await _open();
    final result = await _request(
        database.transaction(_store.toJS).objectStore(_store).get(key.toJS));
    return result?.dartify() as String?;
  }

  @override
  Future<void> write(String key, String value) => _change((store) {
        store.put(value.toJS, key.toJS);
      });
  @override
  Future<void> remove(String key) => _change((store) {
        store.delete(key.toJS);
      });
  @override
  Future<Set<String>> keys() async {
    final database = await _open();
    final result = await _request(
        database.transaction(_store.toJS).objectStore(_store).getAllKeys());
    return ((result?.dartify() as List?) ?? []).cast<String>().toSet();
  }
}
