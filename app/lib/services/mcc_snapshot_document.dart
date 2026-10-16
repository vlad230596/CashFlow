import '../models/mcc_lookup_model.dart';

/// Reads transport versions without evaluating bank policy on the client.
/// Version 3 joins server-computed indices to normalized revision entities.
class MccSnapshotDocument {
  MccSnapshotDocument(this.snapshot);
  final Map<String, dynamic> snapshot;
  Map<String, Map<String, Set<int>>>? _activeOffers;

  static bool isValid(Map<String, dynamic> value) {
    try {
      final reader = MccSnapshotDocument(value);
      reader._validate();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _validate() {
    if (![1, 2, 3].contains(snapshot['schema_version'])) {
      throw const FormatException('Unsupported MCC snapshot');
    }
    for (final key in ['as_of', 'generated_at']) {
      if (snapshot[key] != null && snapshot[key] is! String) {
        throw const FormatException('Invalid MCC timestamp');
      }
    }
    for (final item in snapshot['catalogue'] as List? ?? []) {
      MccCodeModel.fromJson(item as Map<String, dynamic>);
    }
    for (final item in (snapshot['lookups'] as Map? ?? {}).values) {
      MccLookupModel.fromJson(item as Map<String, dynamic>);
    }
    for (final item in (snapshot['offer_rules'] as Map? ?? {}).values) {
      if (item != null) {
        OfferMccRulesModel.fromJson(item as Map<String, dynamic>);
      }
    }
    if (snapshot['schema_version'] == 1) return;
    for (final item
        in (snapshot['mcc_details'] as Map<String, dynamic>).values) {
      MccCodeModel.fromJson(item as Map<String, dynamic>);
    }
    if (snapshot['schema_version'] == 2) {
      final payloads = snapshot['lookup_payloads'] as Map<String, dynamic>;
      for (final item in payloads.values) {
        MccBankRuleModel.fromJson(resolve(item) as Map<String, dynamic>);
      }
      for (final refs
          in (snapshot['lookup_refs'] as Map<String, dynamic>).values) {
        for (final ref in refs as List) {
          if (!payloads.containsKey(ref)) {
            throw const FormatException('Missing MCC lookup');
          }
        }
      }
      final rules = snapshot['offer_rule_payloads'] as Map<String, dynamic>;
      for (final item in rules.values) {
        OfferMccRulesModel.fromJson(resolve(item) as Map<String, dynamic>);
      }
      for (final ref
          in (snapshot['offer_rule_refs'] as Map<String, dynamic>).values) {
        if (ref != null && !rules.containsKey(ref)) {
          throw const FormatException('Missing offer rules');
        }
      }
      for (final value
          in (snapshot['canonical'] as Map<String, dynamic>? ?? {}).values) {
        resolve(value);
      }
      return;
    }
    _validateV3();
  }

  List<Map<String, dynamic>> get _revisions =>
      (snapshot['revisions'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get _bindings =>
      snapshot['offer_bindings'] as Map<String, dynamic>;

  void _validateV3() {
    final banks = snapshot['banks'] as Map<String, dynamic>;
    final revisions = <String, Map<String, dynamic>>{};
    final categoryIds = <String, Set<int>>{};
    for (final revision in _revisions) {
      final id = '${revision['id'] as int}';
      if (revisions.containsKey(id) ||
          !banks.containsKey('${revision['bank_id'] as int}')) {
        throw const FormatException('Invalid MCC revision identity');
      }
      revisions[id] = revision;
      revision['program'] as Map<String, dynamic>;
      revision['source'] as Map<String, dynamic>;
      revision['completeness'] as String;
      final ids = <int>{};
      for (final category
          in (revision['categories'] as List).cast<Map<String, dynamic>>()) {
        final categoryId = category['id'] as int;
        if (!ids.add(categoryId)) {
          throw const FormatException('Duplicate MCC category');
        }
        category['name'] as String;
        category['kind'] as String;
        category['completeness'] as String;
        category['included_mcc'] as List;
        category['excluded_mcc'] as List;
        category['canonical'] as List;
      }
      categoryIds[id] = ids;
      for (final exclusion
          in (revision['exclusions'] as List).cast<Map<String, dynamic>>()) {
        exclusion['mcc'] as String;
        exclusion['kind'] as String;
      }
    }
    final canonical = snapshot['canonical_categories'] as Map<String, dynamic>;
    for (final keys
        in (snapshot['canonical_mcc'] as Map<String, dynamic>).values) {
      for (final key in keys as List) {
        if (!canonical.containsKey(key)) {
          throw const FormatException('Missing canonical category');
        }
      }
    }
    for (final byRevision in [
      snapshot['mcc_defaults'] ?? <String, dynamic>{},
      ...(snapshot['mcc_index'] as Map<String, dynamic>).values,
    ]) {
      for (final entry in (byRevision as Map<String, dynamic>).entries) {
        final revision = revisions[entry.key];
        if (revision == null) {
          throw const FormatException('Unknown MCC revision');
        }
        final index = entry.value as Map<String, dynamic>;
        if (!const {
          'excluded',
          'category_only',
          'conditional',
          'category',
          'not_in_categories'
        }.contains(index['status'])) {
          throw const FormatException('Unknown MCC status');
        }
        for (final key in ['category_ids', 'earning_category_ids']) {
          for (final id in index[key] as List) {
            if (!categoryIds[entry.key]!.contains(id)) {
              throw const FormatException('Unknown MCC category');
            }
          }
        }
        final exclusion = index['exclusion_index'];
        if (exclusion != null &&
            (exclusion is! int ||
                exclusion < 0 ||
                exclusion >= (revision['exclusions'] as List).length)) {
          throw const FormatException('Unknown MCC exclusion');
        }
      }
    }
    for (final entry in _bindings.entries) {
      int.parse(entry.key);
      final binding = entry.value as Map<String, dynamic>;
      binding['bank_id'] as int;
      binding['active'] as bool;
      for (final entry
          in (binding['category_ids_by_revision'] as Map<String, dynamic>)
              .entries) {
        if (revisions[entry.key]?['bank_id'] != binding['bank_id']) {
          throw const FormatException('Offer revision bank mismatch');
        }
        for (final id in entry.value as List) {
          if (!categoryIds[entry.key]!.contains(id)) {
            throw const FormatException('Unknown offer category');
          }
        }
      }
    }
  }

  dynamic resolve(dynamic value, [int depth = 0]) {
    if (depth > 50) throw const FormatException('Recursive MCC snapshot');
    if (value is Map<String, dynamic>) {
      if (value.length == 1 && value[r'$ref'] is String) {
        final shared = snapshot['shared_payloads'] as Map<String, dynamic>;
        if (!shared.containsKey(value[r'$ref'])) {
          throw const FormatException('Missing MCC reference');
        }
        return resolve(shared[value[r'$ref']], depth + 1);
      }
      return value.map((key, item) => MapEntry(key, resolve(item, depth + 1)));
    }
    if (value is List) {
      return value.map((item) => resolve(item, depth + 1)).toList();
    }
    return value;
  }

  bool hasDocument(String collection, String id) {
    if ((snapshot[collection] as Map<String, dynamic>?)?.containsKey(id) ??
        false) {
      return true;
    }
    if (snapshot['schema_version'] == 3) {
      return collection == 'lookups'
          ? RegExp(r'^\d{4}$').hasMatch(id)
          : _bindings.containsKey(id);
    }
    if (snapshot['schema_version'] != 2) return false;
    return (snapshot[collection == 'lookups'
            ? 'lookup_refs'
            : 'offer_rule_refs'] as Map<String, dynamic>)
        .containsKey(id);
  }

  Map<String, dynamic>? document(String collection, String id) {
    final overrides = snapshot[collection] as Map<String, dynamic>?;
    if (overrides?.containsKey(id) ?? false) {
      return overrides![id] as Map<String, dynamic>?;
    }
    if (snapshot['schema_version'] == 1) return null;
    if (snapshot['schema_version'] == 3) {
      return collection == 'lookups' ? _lookupV3(id) : _offerV3(id);
    }
    if (collection == 'lookups') {
      final refs =
          (snapshot['lookup_refs'] as Map<String, dynamic>)[id] as List;
      final payloads = snapshot['lookup_payloads'] as Map<String, dynamic>;
      return {
        'mcc': (snapshot['mcc_details'] as Map<String, dynamic>)[id],
        'banks': refs.map((ref) => resolve(payloads[ref])).toList(),
        'canonical': resolve(
            (snapshot['canonical'] as Map<String, dynamic>? ?? {})[id] ?? []),
        'as_of': snapshot['as_of'],
      };
    }
    final ref = (snapshot['offer_rule_refs'] as Map<String, dynamic>)[id];
    if (ref == null) return null;
    return {
      ...(resolve(
              (snapshot['offer_rule_payloads'] as Map<String, dynamic>)[ref])
          as Map<String, dynamic>),
      'offer_id': int.parse(id),
      'as_of': snapshot['as_of'],
    };
  }

  Map<String, Map<String, Set<int>>> get _offersByCategory =>
      _activeOffers ??= () {
        final result = <String, Map<String, Set<int>>>{};
        for (final entry in _bindings.entries) {
          final binding = entry.value as Map<String, dynamic>;
          if (binding['active'] != true) continue;
          for (final revision
              in (binding['category_ids_by_revision'] as Map<String, dynamic>)
                  .entries) {
            final categories = result.putIfAbsent(revision.key, () => {});
            for (final category in revision.value as List) {
              categories
                  .putIfAbsent('$category', () => {})
                  .add(int.parse(entry.key));
            }
          }
        }
        return result;
      }();

  Map<String, dynamic> _lookupV3(String code) {
    final byRevision = (snapshot['mcc_index'] as Map<String, dynamic>)[code]
            as Map<String, dynamic>? ??
        {};
    final banks = snapshot['banks'] as Map<String, dynamic>;
    final defaults = snapshot['mcc_defaults'] as Map<String, dynamic>? ?? {};
    final canonical = snapshot['canonical_categories'] as Map<String, dynamic>;
    final keys =
        (snapshot['canonical_mcc'] as Map<String, dynamic>)[code] as List? ??
            [];
    return {
      'mcc': (snapshot['mcc_details'] as Map<String, dynamic>)[code] ??
          {'code': code},
      'as_of': snapshot['as_of'],
      'canonical': keys.map((key) => canonical[key]).toList(),
      'banks': [
        for (final revision in _revisions)
          _bankV3(
              revision,
              (byRevision['${revision['id']}'] ?? defaults['${revision['id']}'])
                      as Map<String, dynamic>? ??
                  {},
              banks)
      ],
    };
  }

  Map<String, dynamic> _bankV3(Map<String, dynamic> revision,
      Map<String, dynamic> index, Map<String, dynamic> banks) {
    final ids = (index['category_ids'] as List? ?? []).toSet();
    final categories =
        (revision['categories'] as List).cast<Map<String, dynamic>>();
    final exclusion = index['exclusion_index'] as int?;
    final offers = <int>{};
    final byCategory = _offersByCategory['${revision['id']}'] ?? {};
    for (final id in index['earning_category_ids'] as List? ?? []) {
      offers.addAll(byCategory['$id'] ?? {});
    }
    return {
      'bank': banks['${revision['bank_id']}'],
      'revision_id': revision['id'],
      'program': revision['program'],
      'completeness': revision['completeness'],
      'status': index['status'] ?? 'not_in_categories',
      'exclusion': exclusion == null
          ? null
          : (revision['exclusions'] as List)[exclusion],
      'categories': [
        for (final category in categories)
          if (ids.contains(category['id']))
            {
              'id': category['id'],
              'name': category['name'],
              'kind': category['kind'],
              'canonical': category['canonical'],
            }
      ],
      'offer_ids': offers.toList()..sort(),
    };
  }

  Map<String, dynamic>? _offerV3(String id) {
    final binding = _bindings[id] as Map<String, dynamic>?;
    if (binding == null) return null;
    final byRevision =
        binding['category_ids_by_revision'] as Map<String, dynamic>;
    final details = snapshot['mcc_details'] as Map<String, dynamic>;
    String? title(String code) =>
        (details[code] as Map<String, dynamic>?)?['title'] as String?;
    for (final revision in _revisions) {
      final ids = (byRevision['${revision['id']}'] as List? ?? []).toSet();
      if (ids.isEmpty) continue;
      final category = (revision['categories'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((category) => ids.contains(category['id']));
      return {
        'offer_id': int.parse(id),
        'bank_id': binding['bank_id'],
        'as_of': snapshot['as_of'],
        'revision_id': revision['id'],
        'program': revision['program'],
        'valid_from': revision['valid_from'],
        'valid_to': revision['valid_to'],
        'source': revision['source'],
        'category': {
          'id': category['id'],
          'name': category['name'],
          'description': category['description'],
          'kind': category['kind'],
          'completeness': category['completeness'],
          'conditions': category['conditions'],
          'included': [
            for (final code in category['included_mcc'] as List)
              {'code': code, 'title': title(code as String)}
          ],
          'excluded': [
            for (final code in category['excluded_mcc'] as List)
              {'code': code, 'title': title(code as String)}
          ],
        },
        'exclusions': [
          for (final item
              in (revision['exclusions'] as List).cast<Map<String, dynamic>>())
            {...item, 'title': title(item['mcc'] as String)}
        ],
      };
    }
    return null;
  }
}
