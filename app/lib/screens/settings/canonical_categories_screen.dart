import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/canonical_category_model.dart';
import '../../providers/data_provider.dart';
import '../../utils/cashback_needs.dart';
import '../widgets/keyboard_first_back.dart';
import '../widgets/versioned_app_bar_title.dart';

/// Unified categories and the words that find them in the Benefit search.
class CanonicalCategoriesScreen extends StatefulWidget {
  const CanonicalCategoriesScreen({super.key});

  @override
  State<CanonicalCategoriesScreen> createState() =>
      _CanonicalCategoriesScreenState();
}

class _CanonicalCategoriesScreenState extends State<CanonicalCategoriesScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CanonicalCategoryModel category, String query) =>
      query.isEmpty ||
      normalizeNeedQuery(category.title).contains(query) ||
      normalizeNeedQuery(category.groupTitle).contains(query) ||
      category.aliases
          .any((alias) => normalizeNeedQuery(alias).contains(query));

  void _open(CanonicalCategoryModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CanonicalCategoryEditScreen(categoryKey: category.key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final query = normalizeNeedQuery(_search.text);
    final categories = provider.canonicalCategories
        .where((category) => _matches(category, query))
        .toList();
    final groups = <String, List<CanonicalCategoryModel>>{};
    for (final category in categories) {
      groups.putIfAbsent(category.groupTitle, () => []).add(category);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const KeyboardFirstBackButton(),
        title: const VersionedAppBarTitle(title: 'Категории и синонимы'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('canonical-categories-search'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_outlined),
                  hintText: 'Категория или слово для поиска',
                  helperText: 'Эти слова находят категорию на экране «Выгода»',
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
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.fetchCanonicalCategories,
                child: categories.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              provider.canonicalCategories.isEmpty
                                  ? 'Справочник категорий ещё не загружен. '
                                      'Потяните вниз, чтобы обновить.'
                                  : 'Ни одна категория не находится по '
                                      'слову «${_search.text.trim()}». '
                                      'Добавьте его в синонимы нужной '
                                      'категории.',
                              key: const Key('canonical-categories-empty'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                entry.key,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            for (final category in entry.value)
                              ListTile(
                                key: Key('canonical-category-${category.key}'),
                                title: Text(category.title),
                                subtitle: Text(
                                  category.aliases.isEmpty
                                      ? 'Синонимов нет'
                                      : category.aliases.join(', '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(category),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One unified category: its synonyms, editable by editors and admins.
class CanonicalCategoryEditScreen extends StatefulWidget {
  const CanonicalCategoryEditScreen({super.key, required this.categoryKey});

  final String categoryKey;

  @override
  State<CanonicalCategoryEditScreen> createState() =>
      _CanonicalCategoryEditScreenState();
}

class _CanonicalCategoryEditScreenState
    extends State<CanonicalCategoryEditScreen> {
  final _newAlias = TextEditingController();
  List<String>? _aliases;
  bool _saving = false;

  @override
  void dispose() {
    _newAlias.dispose();
    super.dispose();
  }

  CanonicalCategoryModel? _category(DataProvider provider) {
    for (final item in provider.canonicalCategories) {
      if (item.key == widget.categoryKey) return item;
    }
    return null;
  }

  bool _changed(CanonicalCategoryModel category) {
    final aliases = _aliases;
    if (aliases == null) return false;
    if (aliases.length != category.aliases.length) return true;
    for (var i = 0; i < aliases.length; i++) {
      if (aliases[i] != category.aliases[i]) return true;
    }
    return false;
  }

  void _addAlias(CanonicalCategoryModel category) {
    final alias = _newAlias.text.trim().split(RegExp(r'\s+')).join(' ');
    if (alias.isEmpty) return;
    final aliases = [...(_aliases ?? category.aliases)];
    final folded = normalizeNeedQuery(alias);
    if (!aliases.any((item) => normalizeNeedQuery(item) == folded)) {
      aliases.add(alias);
    }
    setState(() => _aliases = aliases);
    _newAlias.clear();
  }

  void _removeAlias(CanonicalCategoryModel category, String alias) {
    setState(
        () => _aliases = [...(_aliases ?? category.aliases)]..remove(alias));
  }

  Future<void> _save(CanonicalCategoryModel category) async {
    if (_newAlias.text.trim().isNotEmpty) _addAlias(category);
    final provider = context.read<DataProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await provider.updateCanonicalCategoryAliases(
          category.key, _aliases ?? category.aliases);
      if (!mounted) return;
      setState(() => _aliases = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Синонимы сохранены')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final category = _category(provider);
    if (category == null) {
      return Scaffold(
        appBar: AppBar(leading: const KeyboardFirstBackButton()),
        body: const Center(child: Text('Категория не найдена')),
      );
    }
    final canEdit = provider.canEdit;
    final aliases = _aliases ?? category.aliases;
    final changed = _changed(category);
    final theme = Theme.of(context);

    return PopScope(
      canPop: !changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || dismissKeyboardIfVisible(context)) return;
        final navigator = Navigator.of(context);
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Не сохранять изменения?'),
            content: const Text('Изменённые синонимы будут потеряны.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Остаться'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Не сохранять'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          setState(() => _aliases = null);
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const KeyboardFirstBackButton(),
          title: VersionedAppBarTitle(title: category.title),
          actions: [
            if (canEdit)
              TextButton(
                key: const Key('canonical-category-save'),
                onPressed: changed && !_saving ? () => _save(category) : null,
                child: const Text('Сохранить'),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(category.groupTitle,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(category.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text(
                'Поиск на экране «Выгода» находит эту категорию по её '
                'названию и по любому из слов ниже. Достаточно начала '
                'слова: «запр» найдёт «заправки».',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Синонимы', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (aliases.isEmpty)
                const Text('Синонимов нет')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final alias in aliases)
                      InputChip(
                        key: Key('canonical-alias-$alias'),
                        label: Text(alias),
                        onDeleted: canEdit
                            ? () => _removeAlias(category, alias)
                            : null,
                        deleteButtonTooltipMessage: 'Удалить',
                      ),
                  ],
                ),
              if (canEdit) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const Key('canonical-alias-input'),
                  controller: _newAlias,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addAlias(category),
                  decoration: InputDecoration(
                    labelText: 'Новый синоним',
                    hintText: 'Например, бензин',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const Key('canonical-alias-add'),
                      tooltip: 'Добавить',
                      onPressed: () => _addAlias(category),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  'Изменять синонимы могут редактор и администратор.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
