import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/mcc_rule_model.dart';
import '../../providers/data_provider.dart';
import '../widgets/versioned_app_bar_title.dart';

class MccRuleEditScreen extends StatefulWidget {
  const MccRuleEditScreen({
    super.key,
    required this.bank,
    this.baseRevision,
  });

  final BankModel bank;
  final MccRuleRevisionModel? baseRevision;

  @override
  State<MccRuleEditScreen> createState() => _MccRuleEditScreenState();
}

class _CategoryDraft {
  _CategoryDraft({
    String sourceKey = '',
    String name = '',
    String description = '',
    String includedMcc = '',
    String excludedMcc = '',
    this.sourceExternalId,
    this.conditions = const [],
  })  : sourceKey = TextEditingController(text: sourceKey),
        name = TextEditingController(text: name),
        description = TextEditingController(text: description),
        includedMcc = TextEditingController(text: includedMcc),
        excludedMcc = TextEditingController(text: excludedMcc);

  factory _CategoryDraft.fromModel(MccBankCategoryModel model) =>
      _CategoryDraft(
        sourceKey: model.sourceKey,
        name: model.name,
        description: model.description ?? '',
        includedMcc: model.includedMcc.join(', '),
        excludedMcc: model.excludedMcc.join(', '),
        sourceExternalId: model.sourceExternalId,
        conditions: model.conditions,
      );

  final TextEditingController sourceKey;
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController includedMcc;
  final TextEditingController excludedMcc;
  final String? sourceExternalId;
  final List<MccRuleConditionModel> conditions;

  void dispose() {
    sourceKey.dispose();
    name.dispose();
    description.dispose();
    includedMcc.dispose();
    excludedMcc.dispose();
  }
}

class _MccRuleEditScreenState extends State<MccRuleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _programKey;
  late final TextEditingController _programName;
  late final TextEditingController _productScope;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _globalExcludedMcc;
  late DateTime _validFrom;
  DateTime? _validTo;
  late String _validityConfidence;
  late String _completeness;
  late List<_CategoryDraft> _categories;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final base = widget.baseRevision;
    final today = DateTime.now();
    _programKey = TextEditingController(
      text: base?.programKey ?? 'default_cashback',
    );
    _programName = TextEditingController(
      text: base?.programName ?? 'Основная программа кешбэка',
    );
    _productScope = TextEditingController(text: base?.productScope ?? '');
    _sourceUrl = TextEditingController(text: base?.sourceUrl ?? '');
    _globalExcludedMcc = TextEditingController(
      text: base?.globalExcludedMcc.join(', ') ?? '',
    );
    _validFrom = base?.validFrom.toLocal() ?? DateTime(today.year, today.month);
    _validTo = base?.validTo?.toLocal();
    _validityConfidence = base?.validityConfidence ?? 'unknown';
    _completeness = base?.completeness ?? 'unknown';
    _categories = base?.categories.map(_CategoryDraft.fromModel).toList() ?? [];
  }

  @override
  void dispose() {
    _programKey.dispose();
    _programName.dispose();
    _productScope.dispose();
    _sourceUrl.dispose();
    _globalExcludedMcc.dispose();
    for (final category in _categories) {
      category.dispose();
    }
    super.dispose();
  }

  List<String> _parseMcc(String value, String label) {
    final codes = value
        .split(RegExp(r'[\s,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    for (final code in codes) {
      if (!RegExp(r'^\d{4}$').hasMatch(code)) {
        throw FormatException('$label: «$code» — MCC должен содержать 4 цифры');
      }
    }
    return codes;
  }

  String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime? date) =>
      date == null ? 'Не задана' : _isoDate(date);

  Future<void> _pickDate({required bool end}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: end ? (_validTo ?? _validFrom) : _validFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (end) {
        _validTo = selected;
      } else {
        _validFrom = selected;
      }
    });
  }

  void _addCategory() {
    setState(() => _categories.add(_CategoryDraft()));
  }

  void _removeCategory(int index) {
    final removed = _categories.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final globalExcluded = _parseMcc(
        _globalExcludedMcc.text,
        'Глобальные исключения',
      );
      final categoryDocuments = <Map<String, dynamic>>[];
      for (final category in _categories) {
        final included =
            _parseMcc(category.includedMcc.text, category.name.text);
        final excluded =
            _parseMcc(category.excludedMcc.text, category.name.text);
        final overlap = included.toSet().intersection(excluded.toSet());
        if (overlap.isNotEmpty) {
          throw FormatException(
            '${category.name.text}: MCC ${overlap.first} одновременно включён и исключён',
          );
        }
        categoryDocuments.add({
          'sourceKey': category.sourceKey.text.trim(),
          if (category.sourceExternalId != null)
            'sourceId': category.sourceExternalId,
          'name': category.name.text.trim(),
          'description': category.description.text.trim(),
          'includedMcc': included,
          'excludedMcc': excluded,
          'completeness': _completeness,
          'conditions': category.conditions
              .map((condition) => condition.toSnapshotJson())
              .toList(),
        });
      }
      if (_validTo != null && !_validTo!.isAfter(_validFrom)) {
        throw const FormatException(
            'Дата окончания должна быть позже даты начала');
      }

      setState(() => _saving = true);
      final base = widget.baseRevision;
      final result = await context.read<DataProvider>().createMccRuleSnapshot({
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': widget.bank.id,
        'programKey': _programKey.text.trim(),
        'programName': _programName.text.trim(),
        'productScope': _productScope.text.trim().isEmpty
            ? null
            : _productScope.text.trim(),
        'collectedAt': DateTime.now().toUtc().toIso8601String(),
        'source': {
          'type': 'manual_verified',
          'url': _sourceUrl.text.trim().isEmpty ? null : _sourceUrl.text.trim(),
          'parserName': 'cashflow-admin-ui',
          'parserVersion': '1',
        },
        'validity': {
          'from': _isoDate(_validFrom),
          if (_validTo != null) 'to': _isoDate(_validTo!),
          'confidence': _validityConfidence,
        },
        'completeness': _completeness,
        'globalExcludedMcc': globalExcluded,
        'conditions': base?.conditions
                .map((condition) => condition.toSnapshotJson())
                .toList() ??
            [],
        'categories': categoryDocuments,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.status == 'draft'
                ? 'Черновик сохранён'
                : 'Такая версия уже существует',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on FormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: VersionedAppBarTitle(
          title: '${widget.bank.name ?? 'Банк'} · MCC',
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Сохранить'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.baseRevision?.status == 'published')
              const Card(
                color: Color(0xFFFFF8E1),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Вы редактируете опубликованные правила. При сохранении '
                    'будет создан новый черновик.',
                  ),
                ),
              ),
            Text('Программа', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _programKey,
              decoration: const InputDecoration(
                labelText: 'Системный ключ программы',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Укажите ключ программы'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _programName,
              decoration: const InputDecoration(
                labelText: 'Название программы',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Укажите название программы'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _productScope,
              decoration: const InputDecoration(
                labelText: 'Продукт или тариф (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sourceUrl,
              decoration: const InputDecoration(
                labelText: 'Ссылка на источник (необязательно)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(end: false),
                  icon: const Icon(Icons.event),
                  label: Text('Действует с ${_dateLabel(_validFrom)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(end: true),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text('До ${_dateLabel(_validTo)}'),
                ),
                if (_validTo != null)
                  IconButton(
                    tooltip: 'Убрать дату окончания',
                    onPressed: () => setState(() => _validTo = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth < 650
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: _validityConfidence,
                        decoration: const InputDecoration(
                          labelText: 'Точность периода',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'exact', child: Text('Точный')),
                          DropdownMenuItem(
                            value: 'inferred',
                            child: Text('Определён косвенно'),
                          ),
                          DropdownMenuItem(
                            value: 'unknown',
                            child: Text('Неизвестно'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _validityConfidence = value);
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: _completeness,
                        decoration: const InputDecoration(
                          labelText: 'Полнота MCC',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'exact_mcc',
                            child: Text('Полный список'),
                          ),
                          DropdownMenuItem(
                            value: 'partial_mcc',
                            child: Text('Частичный список'),
                          ),
                          DropdownMenuItem(
                            value: 'text_only',
                            child: Text('Только текст'),
                          ),
                          DropdownMenuItem(
                            value: 'unknown',
                            child: Text('Неизвестно'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _completeness = value);
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _globalExcludedMcc,
              decoration: const InputDecoration(
                labelText: 'Глобальные исключения MCC',
                hintText: '0001, 0002',
                helperText: 'Разделяйте коды запятыми или пробелами',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Категории (${_categories.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (index, category) in _categories.indexed)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name.text.isEmpty
                                  ? 'Новая категория'
                                  : category.name.text,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Удалить из новой ревизии',
                            onPressed: () => _removeCategory(index),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: category.sourceKey,
                        decoration: const InputDecoration(
                          labelText: 'Системный ключ категории',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Укажите ключ категории'
                                : null,
                      ),
                      TextFormField(
                        controller: category.name,
                        decoration:
                            const InputDecoration(labelText: 'Название'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Укажите название категории'
                                : null,
                      ),
                      TextFormField(
                        controller: category.description,
                        decoration: const InputDecoration(
                          labelText: 'Исходное описание',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: category.includedMcc,
                        decoration: const InputDecoration(
                          labelText: 'Включённые MCC',
                          hintText: '0002, 0003',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: category.excludedMcc,
                        decoration: const InputDecoration(
                          labelText: 'Исключённые MCC',
                          hintText: '0004',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}
