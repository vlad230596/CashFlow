import 'dart:convert';
import '../models/mcc_rule_model.dart';

enum MccChangeKind { added, changed, removed, unchanged }

class MccCategoryChange {
  const MccCategoryChange({
    required this.kind,
    required this.name,
    required this.sourceKey,
    required this.summary,
    required this.details,
  });

  final MccChangeKind kind;
  final String name;
  final String sourceKey;
  final String summary;
  final String details;
}

class MccImportAnalysis {
  const MccImportAnalysis({
    required this.document,
    required this.programName,
    required this.validFrom,
    required this.validTo,
    required this.completeness,
    required this.sourceType,
    required this.collectedAt,
    required this.categoryCount,
    required this.includedCount,
    required this.excludedCount,
    required this.conditionCount,
    required this.changes,
    required this.errors,
    required this.warnings,
  });

  final Map<String, dynamic> document;
  final String programName;
  final String validFrom;
  final String? validTo;
  final String completeness;
  final String sourceType;
  final String? collectedAt;
  final int categoryCount;
  final int includedCount;
  final int excludedCount;
  final int conditionCount;
  final List<MccCategoryChange> changes;
  final List<String> errors;
  final List<String> warnings;

  int count(MccChangeKind kind) =>
      changes.where((change) => change.kind == kind).length;
}

MccImportAnalysis invalidMccAnalysis(String error) => MccImportAnalysis(
      document: const {},
      programName: 'Не распознано',
      validFrom: '—',
      validTo: null,
      completeness: '—',
      sourceType: '—',
      collectedAt: null,
      categoryCount: 0,
      includedCount: 0,
      excludedCount: 0,
      conditionCount: 0,
      changes: const [],
      errors: [error],
      warnings: const [],
    );

MccImportAnalysis analyzeMccSnapshot(
  Map<String, dynamic> input,
  MccRuleRevisionModel? base,
  int? expectedBankId,
  String? expectedBankKey,
) {
  final errors = <String>[];
  final warnings = <String>[];
  var document = input;
  if (document['schemaVersion'] != 1) {
    errors.add('schemaVersion: ожидается значение 1.');
  }
  if (document['kind'] != 'bank_mcc_rules_snapshot') {
    errors.add('kind: ожидается bank_mcc_rules_snapshot.');
  }
  final bankId = document['bankId'];
  if (bankId is String) {
    // Bundled snapshots name the bank by key (ozon, vtb, …) because database ids differ
    // between environments. The key must match the selected bank's icon key.
    if (expectedBankId == null || bankId != expectedBankKey) {
      errors.add(
        'bankId: файл для банка «$bankId», а выбран банк с ключом '
        '«${expectedBankKey ?? 'не задан'}».',
      );
    } else {
      document = {...document, 'bankId': expectedBankId};
    }
  } else if (bankId is! int) {
    errors.add('bankId: укажите идентификатор или ключ банка.');
  } else if (expectedBankId != null && bankId != expectedBankId) {
    errors.add('bankId: файл относится к другому банку ($bankId).');
  }
  final programName = _requiredString(document, 'programName', errors);
  _requiredString(document, 'programKey', errors);
  final validity = _map(document['validity'], 'validity', errors);
  final validFrom = _requiredString(validity, 'from', errors);
  final validTo = validity['to'] as String?;
  final completeness = document['completeness'] as String? ?? 'не указано';
  if (!{'exact_mcc', 'partial_mcc', 'unknown'}.contains(completeness)) {
    errors.add('completeness: недопустимое значение «$completeness».');
  }
  final source = _map(document['source'], 'source', errors);
  final sourceType = source['type'] as String? ?? 'не указано';
  if (!{'public_page', 'pdf', 'api', 'browser', 'manual_verified'}
      .contains(sourceType)) {
    errors.add('source.type: недопустимое значение «$sourceType».');
  }
  final rawCategories = document['categories'];
  final categories = rawCategories is List ? rawCategories : const [];
  if (rawCategories is! List) errors.add('categories: ожидается массив.');
  final current = <String, Map<String, dynamic>>{};
  var includedCount = 0;
  var excludedCount = 0;
  var conditionCount = _list(document['conditions']).length;
  for (var index = 0; index < categories.length; index++) {
    final raw = categories[index];
    if (raw is! Map<String, dynamic>) {
      errors.add('categories[$index]: ожидается объект.');
      continue;
    }
    final key = raw['sourceKey'] as String?;
    final name = raw['name'] as String?;
    if (key == null || key.trim().isEmpty) {
      errors.add('categories[$index].sourceKey: обязательное поле.');
      continue;
    }
    if (current.containsKey(key)) {
      errors.add('categories[$index].sourceKey: «$key» уже используется.');
      continue;
    }
    if (name == null || name.trim().isEmpty) {
      errors.add('categories[$index].name: обязательное поле.');
    }
    final included =
        _mccList(raw['includedMcc'], 'categories[$index].includedMcc', errors);
    final excluded =
        _mccList(raw['excludedMcc'], 'categories[$index].excludedMcc', errors);
    final overlap = included.toSet().intersection(excluded.toSet());
    if (overlap.isNotEmpty) {
      errors.add(
        'categories[$index]: MCC ${overlap.join(', ')} одновременно включён и исключён.',
      );
    }
    includedCount += included.length;
    excludedCount += excluded.length;
    conditionCount += _list(raw['conditions']).length;
    current[key] = raw;
  }
  final baseCategories = <String, MccBankCategoryModel>{
    for (final item in base?.categories ?? const <MccBankCategoryModel>[])
      item.sourceKey: item,
  };
  final changes = <MccCategoryChange>[];
  for (final entry in current.entries) {
    final raw = entry.value;
    final name = raw['name'] as String? ?? entry.key;
    final included = _stringList(raw['includedMcc']);
    final excluded = _stringList(raw['excludedMcc']);
    final previous = baseCategories.remove(entry.key);
    if (previous == null) {
      changes.add(MccCategoryChange(
        kind: MccChangeKind.added,
        name: name,
        sourceKey: entry.key,
        summary: '${included.length} включённых MCC',
        details: [...included, ...excluded.map((item) => '−$item')].join(', '),
      ));
      continue;
    }
    final same = previous.name == name &&
        _sameSet(previous.includedMcc, included) &&
        _sameSet(previous.excludedMcc, excluded) &&
        previous.description == raw['description'] &&
        previous.sourceExternalId == raw['sourceExternalId'] &&
        previous.kind == (raw['kind'] ?? 'mcc') &&
        previous.completeness == (raw['completeness'] ?? completeness) &&
        _sameSet(previous.manualCanonicalKeys ?? [],
            _stringList(raw['canonicalKeys'])) &&
        _sameJsonItems(
            previous.conditions.map((c) => c.toSnapshotJson()).toList(),
            _list(raw['conditions']));
    if (!same &&
        previous.includedMcc.length >= 4 &&
        included.length * 2 < previous.includedMcc.length) {
      warnings.add(
        'Категория «$name» заметно сократилась: было '
        '${previous.includedMcc.length} включённых MCC, стало ${included.length}.',
      );
    }
    changes.add(MccCategoryChange(
      kind: same ? MccChangeKind.unchanged : MccChangeKind.changed,
      name: name,
      sourceKey: entry.key,
      summary: same
          ? 'Правила категории совпадают'
          : 'Изменены правила · ${included.length} включений · ${excluded.length} исключений',
      details: [...included, ...excluded.map((item) => '−$item')].join(', '),
    ));
  }
  for (final previous in baseCategories.values) {
    changes.add(MccCategoryChange(
      kind: MccChangeKind.removed,
      name: previous.name,
      sourceKey: previous.sourceKey,
      summary: 'Категория отсутствует в новом наборе',
      details: previous.includedMcc.join(', '),
    ));
  }
  if (base != null) {
    final beforeExclusions = base.exclusions.isEmpty
        ? [
            for (final code in base.globalExcludedMcc)
              {'mcc': code, 'kind': 'always', 'reason': null}
          ]
        : [
            for (final exclusion in base.exclusions)
              {
                'mcc': exclusion.mcc,
                'kind': exclusion.kind,
                'reason': exclusion.reason
              }
          ];
    final afterExclusions = _normalizedExclusions(document);
    final programChanged = base.programName != programName ||
        base.programKey != document['programKey'] ||
        base.productScope != document['productScope'] ||
        base.completeness != completeness ||
        base.validityConfidence != (validity['confidence'] ?? 'unknown') ||
        !_sameJsonItems(base.conditions.map((c) => c.toSnapshotJson()).toList(),
            _list(document['conditions'])) ||
        !_sameJsonItems(beforeExclusions, afterExclusions) ||
        base.validFrom != DateTime.tryParse(validFrom) ||
        base.validTo != (validTo == null ? null : DateTime.tryParse(validTo));
    if (programChanged) {
      changes.add(MccCategoryChange(
          kind: MccChangeKind.changed,
          name: 'Правила программы',
          sourceKey: '__program__',
          summary: 'Изменены условия, исключения или параметры программы',
          details: jsonEncode({
            'conditions': document['conditions'] ?? [],
            'exclusions': afterExclusions,
            'validity': validity
          })));
    }
  }
  if (categories.isEmpty) {
    warnings.add(
        'Набор категорий пуст. Backend пока не блокирует публикацию пустого набора.');
  }
  return MccImportAnalysis(
    document: document,
    programName: programName,
    validFrom: validFrom,
    validTo: validTo,
    completeness: completeness,
    sourceType: sourceType,
    collectedAt: document['collectedAt'] as String?,
    categoryCount: current.length,
    includedCount: includedCount,
    excludedCount: excludedCount,
    conditionCount: conditionCount,
    changes: changes,
    errors: errors,
    warnings: warnings,
  );
}

Map<String, dynamic> _map(dynamic value, String path, List<String> errors) {
  if (value is Map<String, dynamic>) return value;
  errors.add('$path: ожидается объект.');
  return const {};
}

String _requiredString(
  Map<String, dynamic> map,
  String key,
  List<String> errors,
) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) return value;
  errors.add('$key: обязательная непустая строка.');
  return '—';
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

List<String> _mccList(dynamic value, String path, List<String> errors) {
  if (value is! List) {
    errors.add('$path: ожидается массив.');
    return const [];
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final code = value[index];
    if (code is! String || !RegExp(r'^\d{4}$').hasMatch(code)) {
      errors.add('$path[$index]: MCC должен быть строкой из четырёх цифр.');
    } else {
      result.add(code);
    }
  }
  return result;
}

List<String> _stringList(dynamic value) =>
    value is List ? value.whereType<String>().toList() : const [];

bool _sameSet(List<String> left, List<String> right) =>
    left.length == right.length && left.toSet().containsAll(right);

String _canonicalJson(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}

bool _sameJsonItems(List<dynamic> left, List<dynamic> right) => _sameSet(
    left.map(_canonicalJson).toList(), right.map(_canonicalJson).toList());

List<Map<String, dynamic>> _normalizedExclusions(
    Map<String, dynamic> document) {
  const precedence = ['always', 'unless_category', 'conditional'];
  final merged = <String, Map<String, dynamic>>{
    for (final code in _stringList(document['globalExcludedMcc']))
      code: {'kind': 'always', 'reasons': <String>[]},
  };
  for (final raw in _list(document['exclusions'])) {
    if (raw is! Map) continue;
    final kind = raw['kind'] ?? 'always';
    final reason = raw['reason']?.toString().trim();
    for (final code in _stringList(raw['mcc'])) {
      final entry =
          merged.putIfAbsent(code, () => {'kind': kind, 'reasons': <String>[]});
      if (precedence.indexOf(kind) < precedence.indexOf(entry['kind'])) {
        entry['kind'] = kind;
      }
      final reasons = entry['reasons'] as List<String>;
      if (reason != null && reason.isNotEmpty && !reasons.contains(reason)) {
        reasons.add(reason);
      }
    }
  }
  return [
    for (final entry in merged.entries)
      {
        'mcc': entry.key,
        'kind': entry.value['kind'],
        'reason': (entry.value['reasons'] as List).isEmpty
            ? null
            : (entry.value['reasons'] as List).join('; ')
      }
  ];
}

/// Use the server's normalized document and authoritative diff after preview.
MccImportAnalysis analysisFromMccPreview(Map<String, dynamic> preview,
    MccRuleRevisionModel? base, int? bankId, String? bankKey) {
  final normalized = preview['normalized_document'] as Map<String, dynamic>;
  final local = analyzeMccSnapshot(normalized, base, bankId, bankKey);
  final diff = preview['diff'] as Map<String, dynamic>;
  final names = <String, String>{
    for (final category in base?.categories ?? <MccBankCategoryModel>[])
      category.sourceKey: category.name,
    for (final category
        in (normalized['categories'] as List).whereType<Map<String, dynamic>>())
      category['sourceKey'] as String: category['name'] as String,
  };
  final changes = <MccCategoryChange>[
    for (final category
        in (diff['categories'] as List).whereType<Map<String, dynamic>>())
      MccCategoryChange(
          sourceKey: category['source_key'] as String,
          name:
              names[category['source_key']] ?? category['source_key'] as String,
          kind: MccChangeKind.values.byName(category['status'] as String),
          summary: category['status'] == 'unchanged'
              ? 'Правила категории совпадают'
              : 'Изменения подтверждены сервером',
          details: (category['changed_fields'] as List? ?? []).join(', ')),
  ];
  final programFields = diff['changed_fields'] as List? ?? [];
  if (programFields.isNotEmpty) {
    changes.add(MccCategoryChange(
        kind: MccChangeKind.changed,
        name: 'Правила программы',
        sourceKey: '__program__',
        summary: 'Изменения подтверждены сервером',
        details: programFields.join(', ')));
  }
  return MccImportAnalysis(
      document: local.document,
      programName: local.programName,
      validFrom: local.validFrom,
      validTo: local.validTo,
      completeness: local.completeness,
      sourceType: local.sourceType,
      collectedAt: local.collectedAt,
      categoryCount: local.categoryCount,
      includedCount: local.includedCount,
      excludedCount: local.excludedCount,
      conditionCount: local.conditionCount,
      changes: changes,
      errors: local.errors,
      warnings: local.warnings);
}
