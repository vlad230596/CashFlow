import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mcc_lookup_model.dart';
import 'api_client.dart';
import 'mcc_cache_store.dart';
import 'mcc_snapshot_document.dart';

typedef MccGet = Future<http.Response> Function(
    String path, Map<String, String> headers);

class _MccContext {
  _MccContext(this.identity, this.session, this.environment, this.account,
      this.day, this.key);
  final String identity, environment, key;
  final int session;
  final int? account;
  final DateTime day;
  Map<String, dynamic>? base;
  Map<String, dynamic> overlay = {
    '_mcc_overlay': 1,
    'lookups': <String, dynamic>{},
    'offer_rules': <String, dynamic>{}
  };
  Future<void>? load;
  final pending = <String, Future<dynamic>>{};
  final attempted = <String, DateTime>{};
  int bindingEpoch = 0;
  int answerVersion = 0;
  int snapshotVersion = 0;
  int snapshotBindingEpoch = 0;
  String? etag;
  bool persistedBase = false;
  bool get bindingsInvalid => overlay['bindings_invalidated'] == true;
  String get asOf =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}T12:00:00+03:00';
}

/// Offline-first MCC data. The complete base is never modified by individual
/// queries: per-day answers are independent overlays, including known 404s.
class MccRepository {
  MccRepository(
      {required this.cache,
      required this.get,
      required this.onChanged,
      this.revalidateAfter = const Duration(minutes: 1),
      this.requestTimeout = const Duration(seconds: 8),
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final MccCacheStore cache;
  final MccGet get;
  final void Function() onChanged;
  final Duration revalidateAfter, requestTimeout;
  final DateTime Function() _now;
  _MccContext? _context;
  Future<void> _writes = Future.value();
  int revision = 0;
  bool _disposed = false;

  String get contextIdentity => _context?.identity ?? '';
  bool get offlineReady =>
      _context?.persistedBase == true &&
      _context?.base != null &&
      ((_context!.base!['schema_version'] as int? ?? 0) >= 2 ||
          _context!.base!['_complete'] == true);
  DateTime? get snapshotUpdatedAt =>
      DateTime.tryParse(_context?.base?['generated_at'] as String? ?? '');
  List<MccCodeModel> get catalogue =>
      ((_context?.overlay['catalogue'] ?? _context?.base?['catalogue'])
                  as List? ??
              [])
          .map((item) => MccCodeModel.fromJson(item as Map<String, dynamic>))
          .toList();

  void activate(String environment, int? account, DateTime day, int session) {
    final identity = cache.key(environment, account, day);
    if (_context?.identity == identity && _context?.session == session) return;
    _context =
        _MccContext(identity, session, environment, account, day, identity);
  }

  void clear() {
    _context = null;
    revision++;
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  bool _current(_MccContext context) =>
      !_disposed && identical(context, _context);
  void _changed(_MccContext context) {
    if (!_current(context)) return;
    revision++;
    onChanged();
  }

  Future<void> load() {
    final context = _context!;
    return context.load ??= () async {
      final exact = await cache.read(context.key);
      final latest = exact ??
          await cache
              .read(cache.latestKey(context.environment, context.account));
      final overlay = await cache.readOverlay(context.key);
      if (!_current(context)) return;
      context.base = latest;
      context.persistedBase = latest != null;
      if (context.bindingsInvalid) {
        context.bindingEpoch += overlay?['binding_epoch'] as int? ?? 0;
        context.overlay = {
          ...context.overlay,
          'binding_epoch': context.bindingEpoch
        };
        await _persist(context, overlay: true);
      } else if (overlay != null) {
        context.overlay = overlay;
        context.bindingEpoch = overlay['binding_epoch'] as int? ?? 0;
        context.answerVersion = overlay['answer_version'] as int? ?? 0;
      }
      // Restore the persisted dirty flag before deciding whether the base
      // validator is reusable. Re-evaluate after the awaited dirty write too:
      // a mutation may invalidate bindings while loading is still in flight.
      context.etag =
          context.bindingsInvalid ? null : latest?['_etag'] as String?;
    }();
  }

  Future<void> _persist(_MccContext context,
      {Map<String, dynamic>? base, bool overlay = false}) {
    // Serialize captured immutable values, never an object later mutated by a
    // different response. One writer also prevents stale latest-pointer races.
    final capturedOverlay = overlay
        ? json.decode(json.encode(context.overlay)) as Map<String, dynamic>
        : null;
    final operation = _writes.then((_) async {
      if (base != null) {
        if (await cache.write(context.key, base)) {
          context.persistedBase = true;
          await cache.saveLatest(context.environment, context.account, base,
              snapshotKey: context.key);
        }
      }
      if (capturedOverlay != null) {
        await cache.writeOverlay(context.key, capturedOverlay);
      }
    });
    _writes = operation.catchError((Object _) {});
    return _writes;
  }

  bool _due(_MccContext context, String key) =>
      !context.pending.containsKey(key) &&
      (context.attempted[key] == null ||
          _now().difference(context.attempted[key]!) >= revalidateAfter);
  void _background(Future<dynamic> future) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  Future<void> refreshSnapshot({bool force = false}) async {
    final context = _context!;
    await load();
    if (!_current(context)) return;
    if (context.pending['snapshot'] case final Future<dynamic> pending) {
      final needsRetry =
          force && context.snapshotBindingEpoch != context.bindingEpoch;
      try {
        await pending;
      } catch (_) {
        if (!needsRetry) rethrow;
      }
      if (needsRetry && _current(context)) await refreshSnapshot(force: true);
      return;
    }
    if (!force && !_due(context, 'snapshot')) return;
    context.attempted['snapshot'] = _now();
    final version = ++context.snapshotVersion;
    final epoch = context.bindingEpoch;
    context.snapshotBindingEpoch = epoch;
    final startingAnswerVersion = context.answerVersion;
    final future = () async {
      try {
        final response = await get(
            'mcc/offline-snapshot?schema=3&as_of=${Uri.encodeQueryComponent(context.asOf)}',
            {
              if (context.etag != null) 'If-None-Match': context.etag!
            }).timeout(requestTimeout);
        if (!_current(context) ||
            version != context.snapshotVersion ||
            epoch != context.bindingEpoch) {
          return;
        }
        if (response.statusCode == 304) return;
        if (response.statusCode != 200) {
          throw ApiException('mcc/offline-snapshot', response.statusCode,
              'Не удалось обновить MCC');
        }
        final next = json.decode(response.body) as Map<String, dynamic>;
        if (!MccSnapshotDocument.isValid(next)) {
          throw const FormatException('Invalid MCC snapshot');
        }
        next['_etag'] = response.headers['etag'];
        next['_complete'] = true;
        final oldSemantic = {...?context.base}
          ..remove('generated_at')
          ..remove('_etag');
        final newSemantic = {...next}
          ..remove('generated_at')
          ..remove('_etag');
        final changed = context.etag != next['_etag'] ||
            context.base == null ||
            json.encode(oldSemantic) != json.encode(newSemantic) ||
            context.bindingsInvalid;
        context.snapshotVersion++;
        context.base = next;
        context.etag = next['_etag'] as String?;
        final retained = <String, dynamic>{
          for (final collection in ['lookups', 'offer_rules'])
            collection: <String, dynamic>{
              for (final entry
                  in (context.overlay[collection] as Map<String, dynamic>)
                      .entries)
                if (((entry.value as Map<String, dynamic>)['answer_version']
                            as int? ??
                        0) >
                    startingAnswerVersion)
                  entry.key: entry.value,
            },
        };
        context.overlay = {
          '_mcc_overlay': 1,
          ...retained,
          'binding_epoch': epoch,
          'answer_version': context.answerVersion
        };
        await _persist(context, base: next, overlay: true);
        if (changed) _changed(context);
      } finally {
        context.pending.remove('snapshot');
      }
    }();
    context.pending['snapshot'] = future;
    await future;
  }

  Future<List<MccCodeModel>> fetchCatalogue() async {
    final context = _context!;
    await load();
    if (!_current(context)) throw StateError('MCC context changed');
    if (catalogue.isNotEmpty) {
      if (_due(context, 'catalogue')) _background(_refreshCatalogue(context));
      return catalogue;
    }
    try {
      await _refreshCatalogue(context);
    } catch (_) {}
    return catalogue;
  }

  Future<void> _refreshCatalogue(_MccContext context) async {
    if (context.pending['catalogue'] case final Future<dynamic> pending) {
      await pending;
      return;
    }
    context.attempted['catalogue'] = _now();
    final future = () async {
      try {
        final response = await get('mcc', {}).timeout(requestTimeout);
        if (!_current(context)) return;
        if (response.statusCode != 200) {
          throw ApiException(
              'mcc', response.statusCode, 'Не удалось обновить MCC');
        }
        final next = json.decode(response.body) as List;
        for (final item in next) {
          MccCodeModel.fromJson(item as Map<String, dynamic>);
        }
        final changed = json.encode(
                context.overlay['catalogue'] ?? context.base?['catalogue']) !=
            json.encode(next);
        context.overlay = {...context.overlay, 'catalogue': next};
        await _persist(context, overlay: true);
        if (changed) _changed(context);
      } finally {
        context.pending.remove('catalogue');
      }
    }();
    context.pending['catalogue'] = future;
    await future;
  }

  Map<String, dynamic>? _record(
      _MccContext context, String collection, String id) {
    final records = context.overlay[collection] as Map<String, dynamic>;
    final overlay = records[id] as Map<String, dynamic>?;
    if (overlay != null && overlay['binding_epoch'] == context.bindingEpoch) {
      return overlay;
    }
    final base = context.base;
    if (!cache.hasDocument(base, collection, id)) return null;
    return {
      'status': cache.document(base!, collection, id) == null ? 404 : 200,
      'document': cache.document(base, collection, id),
      'as_of': base['as_of'],
      'updated_at': base['generated_at'],
      'binding_epoch': context.bindingsInvalid ? -1 : context.bindingEpoch
    };
  }

  Map<String, dynamic>? _materialize(
      _MccContext context, Map<String, dynamic> record, String collection) {
    if (record['status'] == 404) return null;
    final raw = record['document'] as Map<String, dynamic>;
    final asOf = DateTime.tryParse(record['as_of'] as String? ?? '');
    final civil = asOf?.toUtc().add(const Duration(hours: 3));
    final staleBindings = record['binding_epoch'] != context.bindingEpoch ||
        civil == null ||
        civil.year != context.day.year ||
        civil.month != context.day.month ||
        civil.day != context.day.day;
    return {
      ...raw,
      '_cached': true,
      '_updated_at': record['updated_at'],
      '_as_of': record['as_of'],
      '_bindings_stale': staleBindings,
      '_offer_links_current': !staleBindings,
      if (collection == 'lookups' && staleBindings)
        'banks': (raw['banks'] as List? ?? [])
            .map((bank) => {
                  ...(bank as Map<String, dynamic>),
                  'offer_ids': <int>[],
                })
            .toList(),
    };
  }

  Future<Map<String, dynamic>?> document(String collection, String id) async {
    final context = _context!;
    await load();
    if (!_current(context)) throw StateError('MCC context changed');
    final cached = _record(context, collection, id);
    final requestKey = '$collection:$id';
    if (cached != null) {
      if (_due(context, requestKey)) {
        _background(_refreshDocument(context, collection, id));
      }
      if (cached['status'] == 404 && collection == 'lookups') {
        throw const ApiException('mcc', 404, 'MCC не найден');
      }
      return _materialize(context, cached, collection);
    }
    return _refreshDocument(context, collection, id);
  }

  Future<Map<String, dynamic>?> _refreshDocument(
      _MccContext context, String collection, String id) async {
    final key = '$collection:$id';
    if (context.pending[key] case final Future<dynamic> pending) {
      return await pending as Map<String, dynamic>?;
    }
    context.attempted[key] = _now();
    final epoch = context.bindingEpoch;
    final snapshotVersion = context.snapshotVersion;
    final future = () async {
      try {
        final path = collection == 'lookups'
            ? 'mcc/$id/bank-rules'
            : 'cashback/$id/mcc-rules';
        final response = await get(
                '$path?as_of=${Uri.encodeQueryComponent(context.asOf)}', {})
            .timeout(requestTimeout);
        if (!_current(context) ||
            epoch != context.bindingEpoch ||
            snapshotVersion != context.snapshotVersion) {
          throw StateError('MCC context changed');
        }
        if (response.statusCode != 200 && response.statusCode != 404) {
          throw ApiException(
              path, response.statusCode, 'Не удалось загрузить MCC');
        }
        final raw = response.statusCode == 404
            ? null
            : json.decode(response.body) as Map<String, dynamic>;
        if (raw != null) {
          if (collection == 'lookups') {
            MccLookupModel.fromJson(raw);
          } else {
            OfferMccRulesModel.fromJson(raw);
          }
        }
        final previous = _record(context, collection, id);
        final next = <String, dynamic>{
          'status': response.statusCode,
          'document': raw,
          'as_of': context.asOf,
          'updated_at': _now().toUtc().toIso8601String(),
          'binding_epoch': epoch,
          'answer_version': ++context.answerVersion
        };
        context.overlay = {
          ...context.overlay,
          'answer_version': context.answerVersion,
          collection: {
            ...(context.overlay[collection] as Map<String, dynamic>),
            id: next,
          }
        };
        await _persist(context, overlay: true);
        if (previous == null ||
            json.encode(previous['document']) != json.encode(raw) ||
            previous['as_of'] != context.asOf ||
            previous['binding_epoch'] != epoch ||
            previous['updated_at'] != next['updated_at']) {
          _changed(context);
        }
        if (response.statusCode == 404 && collection == 'lookups') {
          throw ApiException(path, 404, 'MCC не найден');
        }
        return raw;
      } finally {
        context.pending.remove(key);
      }
    }();
    context.pending[key] = future;
    return future;
  }

  void invalidateBindings() {
    final context = _context;
    if (context == null) return;
    context.bindingEpoch++;
    context.etag = null;
    context.snapshotVersion++;
    context.overlay = {
      '_mcc_overlay': 1,
      'lookups': <String, dynamic>{},
      'offer_rules': <String, dynamic>{},
      'bindings_invalidated': true,
      'binding_epoch': context.bindingEpoch,
      if (context.overlay['catalogue'] != null)
        'catalogue': context.overlay['catalogue']
    };
    context.attempted.clear();
    _background(_persist(context, overlay: true));
    _changed(context);
    _background(refreshSnapshot(force: true));
  }
}
