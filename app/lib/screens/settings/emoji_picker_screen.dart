import 'package:flutter/material.dart';

import '../../utils/emoji_catalog.dart';
import '../../utils/identity_icons.dart';
import '../widgets/keyboard_first_back.dart';

class EmojiPickerScreen extends StatefulWidget {
  const EmojiPickerScreen({super.key, required this.selectedIconKey});

  final String selectedIconKey;

  @override
  State<EmojiPickerScreen> createState() => _EmojiPickerScreenState();
}

class _EmojiPickerScreenState extends State<EmojiPickerScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late Future<List<EmojiEntry>> _catalogue;
  int? _group;

  @override
  void initState() {
    super.initState();
    _catalogue = EmojiCatalog.load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filterChanged() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const KeyboardFirstBackButton(),
          title: const Text('Эмодзи пользователя'),
          actions: [
            IconButton(
              tooltip: 'Лицензии',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showLicensePage(
                  context: context, applicationName: 'CashFlow'),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('emoji-search'),
                      controller: _search,
                      onChanged: (_) => _filterChanged(),
                      decoration: InputDecoration(
                        labelText: 'Поиск эмодзи',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Очистить поиск',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  _filterChanged();
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _group,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Категория'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Все эмодзи')),
                        for (final group in emojiGroupLabels.entries)
                          DropdownMenuItem(
                              value: group.key, child: Text(group.value)),
                      ],
                      onChanged: (value) {
                        _group = value;
                        _filterChanged();
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<List<EmojiEntry>>(
                        future: _catalogue,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: () => setState(() {
                                  _catalogue = EmojiCatalog.load();
                                }),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Повторить загрузку эмодзи'),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final entries = snapshot.data!
                              .where((entry) =>
                                  (_group == null || entry.group == _group) &&
                                  entry.matches(_search.text))
                              .toList();
                          if (entries.isEmpty) {
                            return const Center(
                                child: Text('Эмодзи не найдены'));
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Найдено: ${entries.length}',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      GridView.builder(
                                    controller: _scroll,
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          (constraints.maxWidth / 60)
                                              .floor()
                                              .clamp(1, 12),
                                      mainAxisExtent: 52,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                    itemCount: entries.length,
                                    itemBuilder: (context, index) {
                                      final entry = entries[index];
                                      final selected = entry.emoji ==
                                          userEmoji(widget.selectedIconKey);
                                      final colors =
                                          Theme.of(context).colorScheme;
                                      return Semantics(
                                        button: true,
                                        selected: selected,
                                        label: entry.label,
                                        child: Tooltip(
                                          message: entry.label,
                                          child: OutlinedButton(
                                            key: ValueKey(entry.iconKey),
                                            style: OutlinedButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(48, 48),
                                              backgroundColor: selected
                                                  ? colors.primaryContainer
                                                  : colors.surface,
                                              side: BorderSide(
                                                color: selected
                                                    ? colors.primary
                                                    : colors.outlineVariant,
                                                width: selected ? 2 : 1,
                                              ),
                                            ),
                                            onPressed: () => Navigator.pop(
                                                context, entry.iconKey),
                                            child: ExcludeSemantics(
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  UserIconBadge(
                                                    iconKey: entry.iconKey,
                                                    size: 32,
                                                  ),
                                                  if (selected)
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: Icon(Icons.check,
                                                          size: 14,
                                                          color:
                                                              colors.primary),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
