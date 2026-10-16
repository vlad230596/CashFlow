import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mcc_cache_storage.dart';
import 'mcc_snapshot_document.dart';
import '../models/mcc_lookup_model.dart';

export 'mcc_cache_storage.dart' show MccStorage, MemoryMccStorage;

/// Environment/account/day-scoped snapshots in dedicated durable storage.
/// Complete snapshots and per-code overlays are separate records. Preferences
/// are read only for migration; failed migration leaves the legacy copy intact.
class MccCacheStore {
  MccCacheStore(
      {MccStorage? storage,
      this.maxBytes = 32 * 1024 * 1024,
      this.maxSnapshotsPerScope = 3})
      : _storage = storage ?? createMccStorage();
  final MccStorage _storage;
  final int maxBytes;
  final int maxSnapshotsPerScope;
  final _readers = Expando<MccSnapshotDocument>();
  Future<void> _pending = Future<void>.value();
  static const _orderKey = 'mcc:v2:write-order';
  static final _dated = RegExp(r':\d{4}-\d{2}-\d{2}$');

  String latestKey(String environment, int? account) =>
      'mcc:v1:${Uri.encodeComponent(environment)}:${account ?? "anonymous"}:latest';
  String key(String environment, int? account, DateTime day) =>
      'mcc:v1:${Uri.encodeComponent(environment)}:${account ?? "anonymous"}:'
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  String _scope(String key) => key.substring(0, key.lastIndexOf(':') + 1);
  MccSnapshotDocument _reader(Map<String, dynamic> snapshot) =>
      _readers[snapshot] ??= MccSnapshotDocument(snapshot);

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<String?> _stored(String key) async {
    try {
      return await _storage.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> read(String key,
      {bool followPointer = true}) async {
    try {
      var text = await _stored(key);
      final legacy = text == null;
      if (legacy) text = (await SharedPreferences.getInstance()).getString(key);
      if (text == null) return null;
      final result = jsonDecode(text) as Map<String, dynamic>;
      if (followPointer && result['snapshot_key'] is String) {
        final target = result['snapshot_key'] as String;
        if (!_dated.hasMatch(target) || _scope(target) != _scope(key)) {
          return null;
        }
        final snapshot = await read(target, followPointer: false);
        if (snapshot != null && legacy) await _migrate(key, text);
        return snapshot;
      }
      if (!MccSnapshotDocument.isValid(result)) return null;
      if (legacy) await _migrate(key, text);
      await _touch(key);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _migrate(String key, String text) async {
    try {
      await _storage.write(key, text);
      // The dedicated record is committed before removing its legacy copy.
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {/* A failed migration keeps usable preferences untouched. */}
  }

  Future<bool> write(String key, Map<String, dynamic> snapshot) =>
      _serial(() async {
        if (!MccSnapshotDocument.isValid(snapshot)) return false;
        return _commit(key, snapshot);
      });

  Future<bool> _commit(String key, Map<String, dynamic> value) async {
    final serialized = jsonEncode(value);
    if (utf8.encode(serialized).length > maxBytes) return false;
    final latest = await _latestBase(key);
    if (key.endsWith(':overlay') && latest != null) {
      final baseSize = utf8.encode(await _stored(latest) ?? '').length;
      if (baseSize + utf8.encode(serialized).length > maxBytes) return false;
    }
    try {
      await _storage.write(key, serialized);
    } catch (_) {
      return false;
    }
    // Retirement only follows a successful atomic record replacement.
    try {
      await _prune(key);
    } catch (_) {/* Retry cleanup after the next write. */}
    return true;
  }

  Future<Map<String, dynamic>?> readOverlay(String baseKey) async {
    try {
      final text = await _stored('$baseKey:overlay');
      if (text == null) return null;
      final result = jsonDecode(text) as Map<String, dynamic>;
      if (!_validOverlay(result)) return null;
      await _touch('$baseKey:overlay');
      return result;
    } catch (_) {
      return null;
    }
  }

  bool _validOverlay(Map<String, dynamic> overlay) {
    try {
      if (overlay['_mcc_overlay'] != 1 ||
          overlay['lookups'] is! Map ||
          overlay['offer_rules'] is! Map) {
        return false;
      }
      for (final field in ['binding_epoch', 'answer_version']) {
        final value = overlay[field];
        if (value != null && (value is! int || value < 0)) return false;
      }
      if (overlay['bindings_invalidated'] != null &&
          overlay['bindings_invalidated'] is! bool) {
        return false;
      }
      for (final item in overlay['catalogue'] as List? ?? []) {
        MccCodeModel.fromJson(item as Map<String, dynamic>);
      }
      for (final collection in ['lookups', 'offer_rules']) {
        for (final entry in (overlay[collection] as Map).entries) {
          if (entry.key is! String) return false;
          final record = entry.value as Map;
          if (record['status'] != 200 && record['status'] != 404) return false;
          for (final field in ['as_of', 'updated_at']) {
            if (record[field] != null &&
                (record[field] is! String ||
                    DateTime.tryParse(record[field] as String) == null)) {
              return false;
            }
          }
          for (final field in ['binding_epoch', 'answer_version']) {
            final value = record[field];
            if (value != null && (value is! int || value < 0)) return false;
          }
          if (record['status'] == 404) {
            if (record['document'] != null) return false;
          } else {
            final document = record['document'] as Map<String, dynamic>;
            if (collection == 'lookups') {
              MccLookupModel.fromJson(document);
            } else {
              OfferMccRulesModel.fromJson(document);
            }
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeOverlay(String baseKey, Map<String, dynamic> overlay) =>
      _serial(() async {
        if (!_validOverlay(overlay)) return false;
        return _commit('$baseKey:overlay', overlay);
      });

  Future<void> saveLatest(
          String environment, int? account, Map<String, dynamic> snapshot,
          {required String snapshotKey}) =>
      _serial(() async {
        final pointer = latestKey(environment, account);
        if (!_dated.hasMatch(snapshotKey) ||
            _scope(pointer) != _scope(snapshotKey)) {
          throw ArgumentError('MCC snapshot belongs to another scope');
        }
        if (await _stored(snapshotKey) == null) return;
        await _storage.write(
            pointer, jsonEncode({'snapshot_key': snapshotKey}));
        // The previous latest remains protected until this pointer is committed.
        try {
          await _prune(snapshotKey);
        } catch (_) {/* retry later */}
      });

  Future<void> _prune(String protectedKey) async {
    final latest = await _latestBase(protectedKey);
    final keys = await _storage.keys();
    final orderText = await _stored(_orderKey);
    final order = orderText == null
        ? <String>[]
        : (jsonDecode(orderText) as List).cast<String>();
    final records = keys
        .where((key) =>
            key.startsWith('mcc:v1:') &&
            (_dated.hasMatch(key) || key.endsWith(':overlay')))
        .toSet();
    order.removeWhere((key) => !records.contains(key) || key == protectedKey);
    for (final key in records) {
      if (!order.contains(key) && key != protectedKey) {
        order.add(key);
      }
    }
    order.add(protectedKey);
    final sizes = <String, int>{};
    for (final key in order) {
      sizes[key] = utf8.encode(await _stored(key) ?? '').length;
    }
    var total = sizes.values.fold<int>(0, (a, b) => a + b);
    final scopeCounts = <String, int>{};
    for (final key in order.where(_dated.hasMatch)) {
      scopeCounts.update(_scope(key), (count) => count + 1, ifAbsent: () => 1);
    }
    for (final key in List<String>.from(order)) {
      if (!order.contains(key)) continue;
      if (key == protectedKey ||
          key == latest ||
          '$key:overlay' == protectedKey) {
        continue;
      }
      final overScope = _dated.hasMatch(key) &&
          (scopeCounts[_scope(key)] ?? 0) > maxSnapshotsPerScope;
      if (total <= maxBytes && !overScope) continue;
      await _storage.remove(key);
      order.remove(key);
      total -= sizes[key] ?? 0;
      if (_dated.hasMatch(key)) {
        scopeCounts.update(_scope(key), (count) => count - 1);
        final overlayKey = '$key:overlay';
        await _storage.remove(overlayKey);
        if (order.remove(overlayKey)) {
          total -= sizes[overlayKey] ?? 0;
        }
        for (final pointer
            in keys.where((candidate) => candidate.endsWith(':latest'))) {
          if (await _stored(pointer) == jsonEncode({'snapshot_key': key})) {
            await _storage.remove(pointer);
          }
        }
      }
    }
    await _storage.write(_orderKey, jsonEncode(order));
  }

  Future<String?> _latestBase(String key) async {
    final baseKey =
        key.endsWith(':overlay') ? key.substring(0, key.length - 8) : key;
    try {
      final text = await _stored('${_scope(baseKey)}latest');
      if (text == null) return null;
      final target = (jsonDecode(text) as Map)['snapshot_key'];
      if (target is String &&
          _dated.hasMatch(target) &&
          _scope(target) == _scope(baseKey)) {
        return target;
      }
    } catch (_) {/* Invalid pointers do not protect records from eviction. */}
    return null;
  }

  Future<void> _touch(String key) => _serial(() async {
        try {
          final text = await _stored(_orderKey);
          final order = text == null
              ? <String>[]
              : (jsonDecode(text) as List).cast<String>();
          order.remove(key);
          order.add(key);
          await _storage.write(_orderKey, jsonEncode(order));
        } catch (_) {
          /* Reading remains available when bookkeeping cannot persist. */
        }
      });

  bool hasDocument(
          Map<String, dynamic>? snapshot, String collection, String id) =>
      snapshot != null && _reader(snapshot).hasDocument(collection, id);
  Map<String, dynamic>? document(
          Map<String, dynamic> snapshot, String collection, String id) =>
      _reader(snapshot).document(collection, id);
  dynamic resolve(Map<String, dynamic> snapshot, dynamic value,
          [int depth = 0]) =>
      _reader(snapshot).resolve(value, depth);
}
