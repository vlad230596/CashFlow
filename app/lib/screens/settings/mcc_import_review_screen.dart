import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/mcc_rule_model.dart';
import '../../providers/data_provider.dart';
import '../../services/cashback_import_launcher.dart';
import '../../services/mcc_snapshot_analyzer.dart';
import '../../services/api_client.dart';
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

class _MccImportReviewScreenState extends State<MccImportReviewScreen> {
  final FocusNode _errorFocus = FocusNode(debugLabel: 'MCC import errors');
  CashbackImportFile? _file;
  MccImportAnalysis? _analysis;
  MccChangeKind? _filter;
  String _query = '';
  bool _reading = false;
  bool _warningsReviewed = false;
  bool _submitting = false;
  bool _publishing = false;
  String? _requestError;
  bool _serverPreviewApplied = false;
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
      _serverPreviewApplied = false;
    });
    await Future<void>.delayed(Duration.zero);
    late MccImportAnalysis result;
    try {
      final decoded = json.decode(file.contents);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Корневое значение должно быть объектом');
      }
      result = analyzeMccSnapshot(
        decoded,
        widget.baseRevision,
        widget.bank.id,
        widget.bank.bankKey ?? widget.bank.iconKey,
      );
    } on FormatException catch (error) {
      result = invalidMccAnalysis('JSON: ${error.message}');
    } catch (error) {
      result = invalidMccAnalysis('Не удалось прочитать JSON: $error');
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
      late MccRuleRevisionModel revision;
      if (widget.snapshotCreator case final creator?) {
        revision = await creator(analysis.document);
      } else {
        final provider = context.read<DataProvider>();
        Map<String, dynamic>? preview;
        try {
          preview = await provider.previewMccRuleSnapshot(analysis.document,
              baseRevisionId: widget.baseRevision?.id);
        } on ApiException catch (error) {
          final unavailable = error.statusCode == 501 ||
              (error.statusCode == 404 &&
                  error.message == 'Не удалось проверить снимок MCC');
          if (!unavailable) rethrow;
        }
        if (!mounted) return;
        if (preview != null) {
          final authoritative = analysisFromMccPreview(
              preview,
              widget.baseRevision,
              widget.bank.id,
              widget.bank.bankKey ?? widget.bank.iconKey);
          setState(() {
            _analysis = authoritative;
            _serverPreviewApplied = true;
          });
          revision = await provider
              .createMccRuleSnapshot(authoritative.document, preview: {
            for (final key in [
              'base_revision_id',
              'base_hash',
              'normalized_hash'
            ])
              key: preview[key]
          });
        } else {
          revision = await provider.createMccRuleSnapshot(analysis.document);
        }
      }
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
          '${analysis.changes.where((item) => item.kind != MccChangeKind.unchanged).length} изменений. '
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
          Text(_serverPreviewApplied
              ? 'Изменения проверены сервером перед созданием черновика.'
              : 'Diff рассчитан локально и не является гарантией сервера.'),
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
                    'Добавлено · ${analysis.count(MccChangeKind.added)}',
                    MccChangeKind.added,
                  ),
                  _filterChip(
                    'Изменено · ${analysis.count(MccChangeKind.changed)}',
                    MccChangeKind.changed,
                  ),
                  _filterChip(
                    'Удалено · ${analysis.count(MccChangeKind.removed)}',
                    MccChangeKind.removed,
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

  Widget _filterChip(String label, MccChangeKind? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _changeTile(MccCategoryChange change) {
    final (icon, label) = switch (change.kind) {
      MccChangeKind.added => (Icons.add_circle_outline, 'Добавлено'),
      MccChangeKind.changed => (Icons.change_circle_outlined, 'Изменено'),
      MccChangeKind.removed => (Icons.remove_circle_outline, 'Удалено'),
      MccChangeKind.unchanged => (Icons.check_circle_outline, 'Без изменений'),
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

  Widget _primaryAction(MccImportAnalysis analysis) {
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

  Widget _statusCard(MccImportAnalysis analysis) {
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

  Widget _diagnostics(MccImportAnalysis analysis) {
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

  Widget _metrics(MccImportAnalysis analysis) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metric('Добавлено', analysis.count(MccChangeKind.added)),
        _metric('Изменено', analysis.count(MccChangeKind.changed)),
        _metric('Удалено', analysis.count(MccChangeKind.removed)),
        _metric('Без изменений', analysis.count(MccChangeKind.unchanged)),
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

String _period(String from, String? to) => '$from — ${to ?? 'без ограничения'}';

String _friendlyError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty
      ? 'Не удалось выполнить запрос. Повторите попытку.'
      : text;
}
