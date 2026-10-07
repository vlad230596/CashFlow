import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/mcc_lookup_model.dart';
import '../../models/mcc_rule_model.dart';
import '../../providers/data_provider.dart';
import '../widgets/offer_mcc_rules_section.dart';
import '../widgets/versioned_app_bar_title.dart';
import 'mcc_import_review_screen.dart';
import 'mcc_rule_edit_screen.dart';

class MccRulesSettingsScreen extends StatefulWidget {
  const MccRulesSettingsScreen({super.key});

  @override
  State<MccRulesSettingsScreen> createState() => _MccRulesSettingsScreenState();
}

class _MccRulesSettingsScreenState extends State<MccRulesSettingsScreen> {
  int? _selectedBankId;
  Future<List<MccRuleRevisionModel>>? _revisions;
  bool _initialized = false;
  final _search = TextEditingController();
  Map<String, String?> _titles = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final provider = context.read<DataProvider>();
    final banks = provider.banks;
    if (banks.isNotEmpty) {
      _selectBank(banks.first.id!);
    }
    _search.addListener(() => setState(() {}));
    provider.fetchMccCatalog().then((catalog) {
      if (!mounted) return;
      setState(
        () => _titles = {for (final mcc in catalog) mcc.code: mcc.title},
      );
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  /// A code matches a digit query by prefix and a text query by its title.
  bool _codeMatches(String code) {
    final query = _query;
    if (query.isEmpty) return true;
    if (RegExp(r'^\d+$').hasMatch(query)) return code.startsWith(query);
    return query.length >= 2 &&
        (_titles[code]?.toLowerCase().contains(query) ?? false);
  }

  bool _categoryMatches(MccBankCategoryModel category) =>
      _query.isEmpty ||
      category.name.toLowerCase().contains(_query) ||
      category.includedMcc.any(_codeMatches) ||
      category.excludedMcc.any(_codeMatches);

  String _titled(String code) {
    final title = _titles[code];
    return title == null ? code : '$code — $title';
  }

  void _showCategory(MccBankCategoryModel category) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(category.name, style: Theme.of(context).textTheme.titleLarge),
            if (category.description?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(category.description!.trim()),
            ],
            const SizedBox(height: 12),
            Text(
              'Включены · ${category.includedMcc.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (category.includedMcc.isEmpty) const Text('Коды не перечислены'),
            for (final code in category.includedMcc) _codeTile(code),
            if (category.excludedMcc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Исключены · ${category.excludedMcc.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final code in category.excludedMcc)
                _codeTile(code, color: Theme.of(context).colorScheme.error),
            ],
          ],
        ),
      ),
    );
  }

  Widget _codeTile(String code, {Color? color, String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MccCodeBadge(code: code, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_titles[code] ?? 'Нет в справочнике MCC'),
                  if (note != null)
                    Text(note, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _revisionDetails(MccRuleRevisionModel revision) {
    final searching = _query.isNotEmpty;
    final exclusions =
        revision.exclusions.where((item) => _codeMatches(item.mcc)).toList();
    final categories = revision.categories.where(_categoryMatches).toList();
    return [
      if (exclusions.isNotEmpty)
        ExpansionTile(
          key: ValueKey('exclusions-${revision.id}-$searching'),
          initiallyExpanded: searching,
          dense: true,
          title: Text('Исключения программы · ${exclusions.length}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            for (final item in exclusions)
              _codeTile(
                item.mcc,
                color: item.kind == 'always'
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
                note: [
                  mccExclusionKindLabel(item.kind),
                  if (item.reason?.trim().isNotEmpty ?? false)
                    item.reason!.trim(),
                ].join(' · '),
              ),
          ],
        ),
      for (final category in categories)
        ListTile(
          dense: true,
          onTap: () => _showCategory(category),
          title: Text(category.name),
          trailing: const Icon(Icons.chevron_right),
          subtitle: Text(_categorySummary(category)),
        ),
    ];
  }

  /// Codes found by the search with their meaning, or the plain code lists.
  String _categorySummary(MccBankCategoryModel category) {
    if (_query.isNotEmpty) {
      final included = category.includedMcc.where(_codeMatches).toList();
      final excluded = category.excludedMcc.where(_codeMatches).toList();
      if (included.isNotEmpty || excluded.isNotEmpty) {
        return [
          for (final code in included.take(5)) 'Включён ${_titled(code)}',
          if (included.length > 5) 'и ещё ${included.length - 5}',
          for (final code in excluded.take(5)) 'Исключён ${_titled(code)}',
        ].join('\n');
      }
    }
    return 'Включены: '
        '${category.includedMcc.isEmpty ? 'не указаны' : category.includedMcc.join(', ')}\n'
        'Исключены: '
        '${category.excludedMcc.isEmpty ? 'нет' : category.excludedMcc.join(', ')}';
  }

  void _selectBank(int bankId) {
    setState(() {
      _selectedBankId = bankId;
      _revisions = context.read<DataProvider>().fetchMccRuleRevisions(bankId);
    });
  }

  Future<void> _refresh() async {
    final bankId = _selectedBankId;
    if (bankId == null) return;
    final future = context.read<DataProvider>().fetchMccRuleRevisions(bankId);
    setState(() => _revisions = future);
    await future;
  }

  BankModel? _selectedBank(List<BankModel> banks) {
    for (final bank in banks) {
      if (bank.id == _selectedBankId) return bank;
    }
    return null;
  }

  Future<void> _openEditor(
    BankModel bank, [
    MccRuleRevisionModel? revision,
  ]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MccRuleEditScreen(
          bank: bank,
          baseRevision: revision,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _openImportReview(BankModel bank) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MccImportReviewScreen(bank: bank),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _publish(MccRuleRevisionModel revision) async {
    try {
      await context.read<DataProvider>().publishMccRuleRevision(revision.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ревизия опубликована')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _autoImport(BankModel bank) async {
    try {
      await context.read<DataProvider>().autoImportMccRules(bank.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Правила загружены')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  String _date(DateTime? value) {
    if (value == null) return 'без ограничения';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final banks = context
        .watch<DataProvider>()
        .banks
        .where((bank) => bank.id != null)
        .toList();
    final bank = _selectedBank(banks);

    return Scaffold(
      appBar: AppBar(
        title: const VersionedAppBarTitle(title: 'Правила MCC'),
      ),
      floatingActionButton: bank == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(bank),
              icon: const Icon(Icons.add),
              label: const Text('Новая ревизия'),
            ),
      body: banks.isEmpty
          ? const Center(child: Text('Сначала добавьте банк'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Расширенные настройки',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Опубликованные правила не перезаписываются. '
                        'Любое изменение сохраняется новой ревизией.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          Widget bankPicker() => DropdownButtonFormField<int>(
                                initialValue: _selectedBankId,
                                decoration: const InputDecoration(
                                  labelText: 'Банк',
                                  border: OutlineInputBorder(),
                                ),
                                items: banks
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item.id,
                                        child: Text(
                                          item.name ?? 'Банк ${item.id}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) _selectBank(value);
                                },
                              );
                          final autoButton = OutlinedButton.icon(
                            onPressed:
                                bank == null ? null : () => _autoImport(bank),
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('Подгрузить автоматически'),
                          );
                          final importButton = OutlinedButton.icon(
                            onPressed: bank == null
                                ? null
                                : () => _openImportReview(bank),
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Проверить JSON'),
                          );
                          if (constraints.maxWidth < 650) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                bankPicker(),
                                const SizedBox(height: 8),
                                importButton,
                                const SizedBox(height: 8),
                                autoButton,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: bankPicker()),
                              const SizedBox(width: 8),
                              importButton,
                              const SizedBox(width: 8),
                              autoButton,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('mcc-rules-search'),
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_outlined),
                          hintText: 'MCC, категория или что означает код',
                          helperText: _titles.containsKey(_query)
                              ? _titled(_query)
                              : null,
                          border: const OutlineInputBorder(),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Очистить',
                                  onPressed: _search.clear,
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<MccRuleRevisionModel>>(
                    future: _revisions,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    'Не удалось загрузить правила: ${snapshot.error}'),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _refresh,
                                  child: const Text('Повторить'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final allRevisions = snapshot.data ?? const [];
                      final searching = _query.isNotEmpty;
                      final revisions = searching
                          ? allRevisions
                              .where((revision) =>
                                  revision.categories.any(_categoryMatches) ||
                                  revision.exclusions
                                      .any((item) => _codeMatches(item.mcc)))
                              .toList()
                          : allRevisions;
                      if (searching && revisions.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              RegExp(r'^\d{4}$').hasMatch(_query)
                                  ? '${_titled(_query)}\n\nКод не входит ни в '
                                      'одну категорию банка и не указан '
                                      'в исключениях.'
                                  : 'Ничего не найдено',
                              key: const Key('mcc-rules-search-empty'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      if (revisions.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.rule_folder_outlined,
                                    size: 48),
                                const SizedBox(height: 12),
                                const Text('Для этого банка правил пока нет'),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: bank == null
                                      ? null
                                      : () => _openEditor(bank),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Создать с нуля'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: revisions.length,
                          itemBuilder: (context, index) {
                            final revision = revisions[index];
                            final isDraft = revision.status == 'draft';
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              child: ExpansionTile(
                                key: ValueKey(
                                  'revision-${revision.id}-$searching',
                                ),
                                initiallyExpanded: searching,
                                leading: Icon(
                                  isDraft
                                      ? Icons.edit_note_outlined
                                      : Icons.verified_outlined,
                                  color: isDraft ? Colors.orange : Colors.green,
                                ),
                                title: Text(revision.programName),
                                subtitle: Text(
                                  '${isDraft ? 'Черновик' : 'Опубликовано'} · '
                                  '${_date(revision.validFrom)} — '
                                  '${_date(revision.validTo)} · '
                                  '${revision.categories.length} категорий',
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit' && bank != null) {
                                      _openEditor(bank, revision);
                                    } else if (value == 'publish') {
                                      _publish(revision);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(
                                        isDraft
                                            ? 'Изменить новой ревизией'
                                            : 'Создать версию на основе этой',
                                      ),
                                    ),
                                    if (isDraft)
                                      const PopupMenuItem(
                                        value: 'publish',
                                        child: Text('Опубликовать'),
                                      ),
                                  ],
                                ),
                                children: _revisionDetails(revision),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
