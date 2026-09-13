import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/mcc_rule_model.dart';
import '../../providers/data_provider.dart';
import '../widgets/versioned_app_bar_title.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final banks = context.read<DataProvider>().banks;
    if (banks.isNotEmpty) {
      _selectBank(banks.first.id!);
    }
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
                          if (constraints.maxWidth < 650) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                bankPicker(),
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
                              autoButton,
                            ],
                          );
                        },
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
                      final revisions = snapshot.data ?? const [];
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
                                children: [
                                  if (revision.globalExcludedMcc.isNotEmpty)
                                    ListTile(
                                      dense: true,
                                      title:
                                          const Text('Глобальные исключения'),
                                      subtitle: Text(
                                        revision.globalExcludedMcc.join(', '),
                                      ),
                                    ),
                                  for (final category in revision.categories)
                                    ListTile(
                                      dense: true,
                                      title: Text(category.name),
                                      subtitle: Text(
                                        'Включены: '
                                        '${category.includedMcc.isEmpty ? 'не указаны' : category.includedMcc.join(', ')}\n'
                                        'Исключены: '
                                        '${category.excludedMcc.isEmpty ? 'нет' : category.excludedMcc.join(', ')}',
                                      ),
                                    ),
                                ],
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
