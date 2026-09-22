import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/mcc_rule_model.dart';
import '../../providers/data_provider.dart';
import '../../services/cashback_import_launcher.dart';
import '../widgets/versioned_app_bar_title.dart';

typedef MccSnapshotCreator = Future<MccRuleRevisionModel> Function(
  Map<String, dynamic> document,
);
typedef MccRevisionPublisher = Future<MccRuleRevisionModel> Function(
  int revisionId,
);

class MccImportReviewScreen extends StatefulWidget {
  const MccImportReviewScreen({
    required this.bank,
    this.baseRevision,
    this.initialFile,
    this.filePicker,
    this.snapshotCreator,
    this.revisionPublisher,
    super.key,
  });

  final BankModel bank;
  final MccRuleRevisionModel? baseRevision;
  final CashbackImportFile? initialFile;
  final Future<CashbackImportFile?> Function()? filePicker;
  final MccSnapshotCreator? snapshotCreator;
  final MccRevisionPublisher? revisionPublisher;

  @override
  State<MccImportReviewScreen> createState() => _MccImportReviewScreenState();
}

enum _ChangeKind { added, changed, removed, unchanged }

class _CategoryChange {
  const _CategoryChange({
    required this.kind,
    required this.name,
    required this.sourceKey,
    required this.summary,
    required this.details,
  });

  final _ChangeKind kind;
  final String name;
  final String sourceKey;
  final String summary;
  final String details;
}

class _ImportAnalysis {
  const _ImportAnalysis({
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
  final List<_CategoryChange> changes;
  final List<String> errors;
  final List<String> warnings;

  int count(_ChangeKind kind) =>
      changes.where((change) => change.kind == kind).length;
}

class _MccImportReviewScreenState extends State<MccImportReviewScreen> {
  final FocusNode _errorFocus = FocusNode(debugLabel: 'MCC import errors');
  CashbackImportFile? _file;
  _ImportAnalysis? _analysis;
  _ChangeKind? _filter;
  String _query = '';
  bool _reading = false;
  bool _warningsReviewed = false;
  bool _submitting = false;
  bool _publishing = false;
  String? _requestError;
  MccRuleRevisionModel? _revision;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFile;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _read(initial));
    }
  }

  @override
  void dispose() {
    _errorFocus.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final selected = await (widget.filePicker ?? pickCashbackImportFile)();
      if (selected != null) await _read(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() => _requestError = _friendlyError(error));
      _focusErrors();
    }
  }

  Future<void> _read(CashbackImportFile file) async {
    setState(() {
      _reading = true;
      _file = file;
      _requestError = null;
      _revision = null;
      _warningsReviewed = false;
    });
    await Future<void>.delayed(Duration.zero);
    late _ImportAnalysis result;
    try {
      final decoded = json.decode(file.contents);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Корневое значение должно быть объектом');
      }
      result = _analyze(decoded, widget.baseRevision, widget.bank.id);
    } on FormatException catch (error) {
      result = _invalidAnalysis('JSON: ${error.message}');
    } catch (error) {
      result = _invalidAnalysis('Не удалось прочитать JSON: $error');
    }
    if (!mounted) return;
    setState(() {
      _analysis = result;
      _reading = false;
      _filter = null;
      _query = '';
    });
    if (result.errors.isNotEmpty) _focusErrors();
  }

  void _focusErrors() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _errorFocus.requestFocus();
    });
  }

  Future<void> _createDraft() async {
    final analysis = _analysis;
    if (analysis == null || analysis.errors.isNotEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _requestError = null;
    });
    try {
      final creator = widget.snapshotCreator ??
          context.read<DataProvider>().createMccRuleSnapshot;
      final revision = await creator(analysis.document);
      if (!mounted) return;
      setState(() => _revision = revision);
    } catch (error) {
      if (!mounted) return;
      setState(() => _requestError = _friendlyError(error));
      _focusErrors();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmPublish() async {
    final revision = _revision;
    final analysis = _analysis;
    if (revision == null || analysis == null || revision.status != 'draft') {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Опубликовать ревизию?'),
        content: Text(
          '${widget.bank.name ?? 'Банк'} · ${analysis.programName}\n'
          '${_period(analysis.validFrom, analysis.validTo)}\n'
          '${analysis.changes.where((item) => item.kind != _ChangeKind.unchanged).length} изменений. '
          'После публикации ревизия станет неизменяемой.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Опубликовать ревизию'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _publish();
  }

  Future<void> _publish() async {
    final revision = _revision;
    if (revision == null || _publishing) return;
    setState(() {
      _publishing = true;
      _requestError = null;
    });
    try {
      final publisher = widget.revisionPublisher ??
          context.read<DataProvider>().publishMccRuleRevision;
      final published = await publisher(revision.id);
      if (mounted) setState(() => _revision = published);
    } catch (error) {
      if (!mounted) return;
      setState(() => _requestError = _friendlyError(error));
      _focusErrors();
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const VersionedAppBarTitle(title: 'Импорт MCC-ревизии'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 840) return _buildReadOnly();
          return _buildExpanded();
        },
      ),
    );
  }

  Widget _buildExpanded() {
    return Column(
      children: [
        _supportNotice(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 250, child: _sourcePanel()),
              const VerticalDivider(width: 1),
              Expanded(flex: 2, child: _previewPanel()),
              const VerticalDivider(width: 1),
              SizedBox(width: 290, child: _summaryPanel(readOnly: false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnly() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.desktop_windows_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Режим сводки. Для импорта и публикации увеличьте ширину '
                    'этого окна минимум до 840 px. Выбранные данные сохранятся.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _summaryPanel(readOnly: true),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Увеличьте ширину текущего окна минимум до 840 px. '
                  'Состояние проверки сохранится.',
                ),
              ),
            );
          },
          icon: const Icon(Icons.open_in_full),
          label: const Text('Открыть в широком окне'),
        ),
      ],
    );
  }

  Widget _supportNotice() {
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline, semanticLabel: 'Информация'),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'JSON snapshot v1 поддерживается сейчас. PDF, CSV, XLSX, URL '
                'и автоматический разбор пока не подключены.',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _reading ? null : _pickFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Выбрать JSON'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePanel() {
    final analysis = _analysis;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Этапы импорта', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Публикация не выполняется автоматически.'),
        const SizedBox(height: 16),
        _step(1, 'Источник', _file == null ? 'Не выбран' : 'JSON выбран'),
        _step(2, 'Проверка', analysis == null ? 'Ожидает' : 'Выполнена'),
        _step(3, 'Preview', analysis == null ? 'Ожидает' : 'Доступен'),
        _step(4, 'Черновик',
            _revision == null ? 'Не создан' : '№${_revision!.id}'),
        _step(
          5,
          'Публикация',
          _revision?.status == 'published' ? 'Опубликовано' : 'Отдельно',
        ),
        const Divider(height: 28),
        Text('Банк', style: Theme.of(context).textTheme.labelMedium),
        Text(widget.bank.name ?? 'Банк ${widget.bank.id ?? '—'}'),
        const SizedBox(height: 12),
        if (_reading) const LinearProgressIndicator(),
        if (_file != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(_file!.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${utf8.encode(_file!.contents).length} байт · JSON snapshot v1',
            ),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Выбрать JSON-файл'),
          ),
        const SizedBox(height: 12),
        const Text(
          'Другие источники недоступны: backend не принимает бинарные файлы '
          'и не предоставляет preview API.',
        ),
        if (widget.baseRevision != null) ...[
          const Divider(height: 28),
          Text('База сравнения', style: Theme.of(context).textTheme.labelLarge),
          Text(
            'Ревизия №${widget.baseRevision!.id} · '
            '${widget.baseRevision!.status == 'published' ? 'опубликована' : 'черновик'}',
          ),
          const Text(
              'Diff рассчитан локально и не является гарантией сервера.'),
        ],
      ],
    );
  }

  Widget _step(int number, String title, String subtitle) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 14, child: Text('$number')),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  Widget _previewPanel() {
    final analysis = _analysis;
    if (_reading) return const Center(child: CircularProgressIndicator());
    if (analysis == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Выберите JSON snapshot v1 для локальной проверки.'),
        ),
      );
    }
    final visible = analysis.changes.where((change) {
      final matchesFilter = _filter == null || change.kind == _filter;
      final needle = _query.toLowerCase();
      return matchesFilter &&
          (needle.isEmpty ||
              change.name.toLowerCase().contains(needle) ||
              change.sourceKey.toLowerCase().contains(needle) ||
              change.summary.contains(needle));
    }).toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              Text(
                'Предварительный просмотр изменений',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Локальное сравнение. Серверный diff пока не реализован.',
              ),
              const SizedBox(height: 12),
              _metrics(analysis),
              if (analysis.errors.isNotEmpty ||
                  analysis.warnings.isNotEmpty ||
                  _requestError != null) ...[
                const SizedBox(height: 12),
                _diagnostics(analysis),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('Все · ${analysis.changes.length}', null),
                  _filterChip(
                    'Добавлено · ${analysis.count(_ChangeKind.added)}',
                    _ChangeKind.added,
                  ),
                  _filterChip(
                    'Изменено · ${analysis.count(_ChangeKind.changed)}',
                    _ChangeKind.changed,
                  ),
                  _filterChip(
                    'Удалено · ${analysis.count(_ChangeKind.removed)}',
                    _ChangeKind.removed,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Поиск в изменениях',
                  hintText: 'Категория или MCC',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Нет изменений по выбранному фильтру')),
          )
        else
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) => _changeTile(visible[index]),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
      ],
    );
  }

  Widget _filterChip(String label, _ChangeKind? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _changeTile(_CategoryChange change) {
    final (icon, label) = switch (change.kind) {
      _ChangeKind.added => (Icons.add_circle_outline, 'Добавлено'),
      _ChangeKind.changed => (Icons.change_circle_outlined, 'Изменено'),
      _ChangeKind.removed => (Icons.remove_circle_outline, 'Удалено'),
      _ChangeKind.unchanged => (Icons.check_circle_outline, 'Без изменений'),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        leading: Icon(icon, semanticLabel: label),
        title: Text(change.name),
        subtitle: Text('$label · ${change.summary}'),
        children: [
          ListTile(
            title: Text(change.details),
            subtitle: Text('sourceKey: ${change.sourceKey}'),
          ),
        ],
      ),
    );
  }

  Widget _summaryPanel({required bool readOnly}) {
    final analysis = _analysis;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          key: const ValueKey('mcc-import-summary-scroll'),
          shrinkWrap: readOnly,
          physics: readOnly ? const NeverScrollableScrollPhysics() : null,
          children: [
            Text('Сводка ревизии',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_reading) const LinearProgressIndicator(),
            if (analysis == null)
              const Text('Данные ещё не выбраны.')
            else ...[
              _statusCard(analysis),
              const SizedBox(height: 12),
              if (readOnly) _metrics(analysis),
              _fact('Банк · программа',
                  '${widget.bank.name ?? 'Банк'} · ${analysis.programName}'),
              _fact('Период действия',
                  _period(analysis.validFrom, analysis.validTo)),
              _fact('Полнота данных', analysis.completeness),
              _fact('Источник', analysis.sourceType),
              _fact('Собрано', analysis.collectedAt ?? 'не указано'),
              _fact(
                'Состав',
                '${analysis.categoryCount} категорий · '
                    '${analysis.includedCount} включений · '
                    '${analysis.excludedCount} исключений · '
                    '${analysis.conditionCount} условий',
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Ограничение: diff и предупреждения рассчитаны клиентом. '
                    'Backend принимает готовый JSON целиком и возвращает ошибку '
                    'контракта без построчной диагностики.',
                  ),
                ),
              ),
              if (!readOnly) ...[
                const SizedBox(height: 16),
                if (analysis.warnings.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _warningsReviewed,
                    onChanged: _revision == null
                        ? (value) => setState(
                              () => _warningsReviewed = value ?? false,
                            )
                        : null,
                    title: const Text('Я просмотрел предупреждения'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                _primaryAction(analysis),
                const SizedBox(height: 8),
                const Text(
                  'Создание черновика не публикует правила. Публикация — '
                  'отдельное подтверждаемое действие.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryAction(_ImportAnalysis analysis) {
    final revision = _revision;
    if (revision?.status == 'published') {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.verified_outlined),
        label: Text('Опубликовано · №${revision!.id}'),
      );
    }
    if (revision != null) {
      return FilledButton.icon(
        onPressed: _publishing ? null : _confirmPublish,
        icon: _publishing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.publish_outlined),
        label: Text(
          _publishing ? 'Публикуем…' : 'Опубликовать ревизию №${revision.id}',
        ),
      );
    }
    final canCreate = analysis.errors.isEmpty &&
        (analysis.warnings.isEmpty || _warningsReviewed) &&
        !_submitting;
    return FilledButton.icon(
      onPressed: canCreate ? _createDraft : null,
      icon: _submitting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.note_add_outlined),
      label: Text(_submitting ? 'Создаём…' : 'Создать черновик'),
    );
  }

  Widget _statusCard(_ImportAnalysis analysis) {
    final hasErrors = analysis.errors.isNotEmpty || _requestError != null;
    final published = _revision?.status == 'published';
    final title = published
        ? 'Ревизия опубликована'
        : _revision != null
            ? 'Черновик создан · №${_revision!.id}'
            : hasErrors
                ? 'Нужны исправления'
                : 'Формат принят';
    return Card(
      color: hasErrors
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          hasErrors ? Icons.error_outline : Icons.check_circle_outline,
          semanticLabel: hasErrors ? 'Ошибка' : 'Успешно',
        ),
        title: Text(title),
        subtitle: Text(
          hasErrors
              ? 'Черновик нельзя создать'
              : 'Блокирующих ошибок не найдено',
        ),
      ),
    );
  }

  Widget _diagnostics(_ImportAnalysis analysis) {
    final errors = [
      if (_requestError != null) _requestError!,
      ...analysis.errors
    ];
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Результаты проверки',
      child: Card(
        key: const ValueKey('mcc-import-diagnostics'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Focus(
            focusNode: _errorFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${errors.length} ошибок · ${analysis.warnings.length} предупреждений',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final error in errors)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text(error),
                  ),
                for (final warning in analysis.warnings)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(warning),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metrics(_ImportAnalysis analysis) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metric('Добавлено', analysis.count(_ChangeKind.added)),
        _metric('Изменено', analysis.count(_ChangeKind.changed)),
        _metric('Удалено', analysis.count(_ChangeKind.removed)),
        _metric('Без изменений', analysis.count(_ChangeKind.unchanged)),
      ],
    );
  }

  Widget _metric(String label, int value) {
    return Semantics(
      label: '$label: $value',
      child: Container(
        constraints: const BoxConstraints(minWidth: 105),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

_ImportAnalysis _invalidAnalysis(String error) => _ImportAnalysis(
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

_ImportAnalysis _analyze(
  Map<String, dynamic> document,
  MccRuleRevisionModel? base,
  int? expectedBankId,
) {
  final errors = <String>[];
  final warnings = <String>[];
  if (document['schemaVersion'] != 1) {
    errors.add('schemaVersion: ожидается значение 1.');
  }
  if (document['kind'] != 'bank_mcc_rules_snapshot') {
    errors.add('kind: ожидается bank_mcc_rules_snapshot.');
  }
  final bankId = document['bankId'];
  if (bankId is! int) {
    errors.add('bankId: укажите целочисленный идентификатор банка.');
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
  final changes = <_CategoryChange>[];
  for (final entry in current.entries) {
    final raw = entry.value;
    final name = raw['name'] as String? ?? entry.key;
    final included = _stringList(raw['includedMcc']);
    final excluded = _stringList(raw['excludedMcc']);
    final previous = baseCategories.remove(entry.key);
    if (previous == null) {
      changes.add(_CategoryChange(
        kind: _ChangeKind.added,
        name: name,
        sourceKey: entry.key,
        summary: '${included.length} включённых MCC',
        details: [...included, ...excluded.map((item) => '−$item')].join(', '),
      ));
      continue;
    }
    final same = previous.name == name &&
        _sameSet(previous.includedMcc, included) &&
        _sameSet(previous.excludedMcc, excluded);
    if (!same &&
        previous.includedMcc.length >= 4 &&
        included.length * 2 < previous.includedMcc.length) {
      warnings.add(
        'Категория «$name» заметно сократилась: было '
        '${previous.includedMcc.length} включённых MCC, стало ${included.length}.',
      );
    }
    changes.add(_CategoryChange(
      kind: same ? _ChangeKind.unchanged : _ChangeKind.changed,
      name: name,
      sourceKey: entry.key,
      summary: same
          ? 'Полный список совпадает'
          : '${included.length} включений · ${excluded.length} исключений',
      details: [...included, ...excluded.map((item) => '−$item')].join(', '),
    ));
  }
  for (final previous in baseCategories.values) {
    changes.add(_CategoryChange(
      kind: _ChangeKind.removed,
      name: previous.name,
      sourceKey: previous.sourceKey,
      summary: 'Категория отсутствует в новом наборе',
      details: previous.includedMcc.join(', '),
    ));
  }
  if (categories.isEmpty) {
    warnings.add(
        'Набор категорий пуст. Backend пока не блокирует публикацию пустого набора.');
  }
  return _ImportAnalysis(
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

String _period(String from, String? to) => '$from — ${to ?? 'без ограничения'}';

String _friendlyError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty
      ? 'Не удалось выполнить запрос. Повторите попытку.'
      : text;
}
