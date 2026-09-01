import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../utils/category_info.dart';
import 'cashback_category_edit_screen.dart';
import 'widgets/cashback_description_button.dart';
import 'widgets/cashback_limits_label.dart';

class ParsedCashbackCategoryLine {
  const ParsedCashbackCategoryLine({
    required this.categoryName,
    required this.percent,
  });

  final String categoryName;
  final double percent;
}

@visibleForTesting
ParsedCashbackCategoryLine parseCashbackCategoryLine(String line) {
  final trimmed = line.trim();
  final percentMatch =
      RegExp(r'(\d+)\s*%|%\s*(\d+)|\b(\d+)\b').firstMatch(trimmed);

  if (percentMatch == null) {
    throw FormatException('Не найден процент в строке: "$trimmed"');
  }

  final percentStr =
      percentMatch.group(1) ?? percentMatch.group(2) ?? percentMatch.group(3);
  final percent = double.parse(percentStr!);
  final categoryName = trimmed
      .replaceRange(percentMatch.start, percentMatch.end, '')
      .trim()
      .replaceAll(
        RegExp(
          r'''^[\s%.,;:|/\\_\-+()[\]{}"'`]+|[\s%.,;:|/\\_\-+()[\]{}"'`]+$''',
        ),
        '',
      )
      .trim();

  if (categoryName.isEmpty) {
    throw FormatException(
      'Не указано название категории в строке: "$trimmed"',
    );
  }

  return ParsedCashbackCategoryLine(
    categoryName: categoryName,
    percent: percent,
  );
}

/// Temporary name-based grouping until MCC codes become structured data.
///
/// The UI keeps the original bank title visible and explicitly describes this
/// match as approximate.
@visibleForTesting
String normalizedCashbackCategoryName(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();

  bool containsAny(Iterable<String> words) =>
      words.any((word) => normalized.contains(word));

  if (containsAny(['аптек', 'лекарств'])) return 'Аптеки';
  if (containsAny(['супермаркет', 'продукт', 'groceries'])) {
    return 'Продукты и супермаркеты';
  }
  if (containsAny(['кафе', 'ресторан', 'фастфуд'])) {
    return 'Кафе и рестораны';
  }
  if (containsAny(['одежд', 'обув', 'fashion'])) return 'Одежда и обувь';
  if (containsAny(['азс', 'топлив', 'заправ'])) return 'АЗС и топливо';
  if (containsAny(['такси', 'каршер'])) return 'Такси и каршеринг';
  if (containsAny(['транспорт', 'метро', 'автобус'])) {
    return 'Общественный транспорт';
  }
  if (containsAny(['дом и ремонт', 'стройматериал', 'товары для дома'])) {
    return 'Дом и ремонт';
  }
  if (containsAny(['спорт', 'фитнес', 'активный отдых'])) {
    return 'Спорт и активный отдых';
  }
  if (containsAny(['кино', 'развлеч'])) return 'Развлечения';
  if (containsAny(['путешеств', 'авиабилет', 'отел', 'travel'])) {
    return 'Путешествия';
  }
  if (containsAny(['все покупки', 'на все', 'everything'])) {
    return 'Все покупки';
  }
  if (containsAny(['онлайн покуп', 'online'])) return 'Онлайн-покупки';

  if (normalized.isEmpty) return value.trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

/// Lower values are shown first. Unknown names are treated as niche offers,
/// including cashback tied to a particular shop or brand.
@visibleForTesting
int cashbackCategorySortPriority(String categoryName) {
  switch (normalizedCashbackCategoryName(categoryName)) {
    case 'Продукты и супермаркеты':
      return 10;
    case 'Кафе и рестораны':
      return 20;
    case 'Одежда и обувь':
      return 30;
    case 'Аптеки':
      return 40;
    case 'Все покупки':
      return 45;
    case 'АЗС и топливо':
      return 50;
    case 'Общественный транспорт':
      return 60;
    case 'Такси и каршеринг':
      return 65;
    case 'Дом и ремонт':
      return 70;
    case 'Спорт и активный отдых':
      return 80;
    case 'Путешествия':
      return 90;
    case 'Онлайн-покупки':
      return 100;
    case 'Развлечения':
      return 110;
    default:
      return 1000;
  }
}

enum _MonthlyView { categories, banks }

enum _CategoryFilter { all, uncovered, duplicates }

class _CategoryGroup {
  const _CategoryGroup({required this.title, required this.offers});

  final String title;
  final List<CashbackCategoryModel> offers;

  bool get isCovered => offers.any((offer) => offer.isSelected);
  int get selectedCount => offers.where((offer) => offer.isSelected).length;
  double get bestPercent => offers.fold<double>(
        0,
        (best, offer) =>
            offer.cashbackPercent > best ? offer.cashbackPercent : best,
      );
}

class MonthlyCashbackScreen extends StatefulWidget {
  const MonthlyCashbackScreen({super.key});

  @override
  State<MonthlyCashbackScreen> createState() => _MonthlyCashbackScreenState();
}

class _MonthlyCashbackScreenState extends State<MonthlyCashbackScreen> {
  static const int _defaultMaxCategories = 3;

  final Map<int, int> _maxCategoriesPerCard = {};
  final Map<int, TextEditingController> _maxCategoriesControllers = {};
  late DateTime _startDate;
  late DateTime _endDate;
  _MonthlyView _view = _MonthlyView.categories;
  _CategoryFilter _filter = _CategoryFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final defaultStartDate = _getDefaultStartDate(DateTime.now());
    _startDate = defaultStartDate;
    _endDate = _getLastDayOfMonth(defaultStartDate);
  }

  @override
  void dispose() {
    for (final controller in _maxCategoriesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  DateTime _getDefaultStartDate(DateTime now) {
    final targetMonth = now.day <= 20 ? now.month : now.month + 1;
    return DateTime(now.year, targetMonth);
  }

  DateTime _getLastDayOfMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0);
  }

  DateTime _getEndOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = DateUtils.dateOnly(picked.start);
        _endDate = DateUtils.dateOnly(picked.end);
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  bool _isCategoryInSelectedPeriod(CashbackCategoryModel category) {
    final categoryStart = DateUtils.dateOnly(category.startDate);
    final categoryEnd = DateUtils.dateOnly(category.endDate);
    return categoryEnd.isAfter(_startDate) && !categoryStart.isAfter(_endDate);
  }

  List<CashbackCategoryModel> _periodCategories(DataProvider dataProvider) {
    return dataProvider.cashbackCategories
        .where(_isCategoryInSelectedPeriod)
        .toList();
  }

  List<_CategoryGroup> _categoryGroups(DataProvider dataProvider) {
    final grouped = <String, List<CashbackCategoryModel>>{};
    for (final category in _periodCategories(dataProvider)) {
      final title = normalizedCashbackCategoryName(category.name);
      grouped.putIfAbsent(title, () => []).add(category);
    }

    final groups = grouped.entries.map((entry) {
      entry.value.sort((a, b) {
        if (a.isSelected != b.isSelected) return a.isSelected ? -1 : 1;
        return b.cashbackPercent.compareTo(a.cashbackPercent);
      });
      return _CategoryGroup(title: entry.key, offers: entry.value);
    }).where((group) {
      if (_filter == _CategoryFilter.uncovered && group.isCovered) return false;
      if (_filter == _CategoryFilter.duplicates && group.selectedCount < 2) {
        return false;
      }
      if (_query.isEmpty) return true;
      final query = _query.toLowerCase();
      return group.title.toLowerCase().contains(query) ||
          group.offers.any((offer) => offer.name.toLowerCase().contains(query));
    }).toList();

    groups.sort((a, b) {
      final priorityComparison = cashbackCategorySortPriority(
        a.title,
      ).compareTo(cashbackCategorySortPriority(b.title));
      if (priorityComparison != 0) return priorityComparison;
      return a.title.compareTo(b.title);
    });
    return groups;
  }

  int _getMaxCategories(int cardId, int? serverValue) {
    return _maxCategoriesPerCard.putIfAbsent(
      cardId,
      () => serverValue ?? _defaultMaxCategories,
    );
  }

  TextEditingController _getMaxController(int cardId, int maxCategories) {
    return _maxCategoriesControllers.putIfAbsent(
      cardId,
      () => TextEditingController(text: maxCategories.toString()),
    );
  }

  int _selectedStandardCount(
    Iterable<CashbackCategoryModel> categories,
    int cardId,
  ) {
    return categories
        .where(
          (category) =>
              category.cardId == cardId &&
              category.isSelected &&
              category.isSelectable,
        )
        .length;
  }

  Future<void> _openCategoryEditor(
    BuildContext context,
    CashbackCategoryModel category,
  ) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashbackCategoryEditScreen(category: category),
      ),
    );
  }

  Future<void> _toggleCategory(
    BuildContext context,
    DataProvider dataProvider,
    CashbackCategoryModel category,
    bool value,
    _CategoryGroup? group,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (category.isTaskBonus) return;
    if (value && !category.isStackableBonus) {
      final card = dataProvider.getCardById(category.cardId);
      final maximum = _getMaxCategories(
        category.cardId,
        card.maxCashbackCategories,
      );
      final selected = _selectedStandardCount(
        _periodCategories(dataProvider),
        category.cardId,
      );
      if (selected >= maximum) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'На этой карте уже выбрано $selected из $maximum категорий. '
              'Сначала освободите место.',
            ),
          ),
        );
        return;
      }
    }

    try {
      await dataProvider.toggleCategorySelection(category.id, value);
      if (!mounted || !value || group == null) return;
      final selectedElsewhere = group.offers.any(
        (offer) => offer.id != category.id && offer.isSelected,
      );
      if (selectedElsewhere) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '«${group.title}» уже покрыта другой картой. '
              'Проверьте, нужен ли дубль.',
            ),
            action: SnackBarAction(
              label: 'Показать',
              onPressed: () => setState(() {
                _filter = _CategoryFilter.duplicates;
              }),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить выбор')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final periodCategories = _periodCategories(dataProvider);
    final visibleGroups = _categoryGroups(dataProvider);
    final totalGroups = <String>{
      for (final category in periodCategories)
        normalizedCashbackCategoryName(category.name),
    }.length;
    final coveredGroups = <String>{
      for (final category in periodCategories)
        if (category.isSelected) normalizedCashbackCategoryName(category.name),
    }.length;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _view == _MonthlyView.categories
                ? _buildCategoryView(context, dataProvider, visibleGroups)
                : _buildBankView(context, dataProvider, periodCategories),
          ),
        ],
      ),
      bottomNavigationBar: _buildSummary(
        context,
        dataProvider,
        periodCategories,
        coveredGroups,
        totalGroups,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final dateButton = OutlinedButton.icon(
              onPressed: () => _showDateRangePicker(context),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(
                '${_formatDate(_startDate)} — ${_formatDate(_endDate)}',
                maxLines: 1,
              ),
            );
            final switcher = SegmentedButton<_MonthlyView>(
              segments: const [
                ButtonSegment(
                  value: _MonthlyView.categories,
                  icon: Icon(Icons.compare_arrows),
                  label: Text('По категориям'),
                ),
                ButtonSegment(
                  value: _MonthlyView.banks,
                  icon: Icon(Icons.account_balance_outlined),
                  label: Text('По банкам'),
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _view = selection.first);
              },
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dateButton,
                  const SizedBox(height: 8),
                  switcher,
                ],
              );
            }
            return Row(
              children: [dateButton, const Spacer(), switcher],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryView(
    BuildContext context,
    DataProvider dataProvider,
    List<_CategoryGroup> groups,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Найти категорию',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Все', _CategoryFilter.all),
              const SizedBox(width: 8),
              _filterChip('Не покрыто', _CategoryFilter.uncovered),
              const SizedBox(width: 8),
              _filterChip('Дубли', _CategoryFilter.duplicates),
              const SizedBox(width: 8),
              const Tooltip(
                message:
                    'Похожие категории пока объединяются по названию. Точное сравнение по MCC появится позже.',
                child: Chip(
                  avatar: Icon(Icons.info_outline, size: 17),
                  label: Text('Сопоставление по названию'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? _buildEmptyCategories()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final cardHeight =
                              (84.0 + group.offers.length * 72).clamp(190, 430);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              height: cardHeight.toDouble(),
                              child: _buildCategoryCard(
                                context,
                                dataProvider,
                                group,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 580,
                        mainAxisExtent: 360,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, index) => _buildCategoryCard(
                        context,
                        dataProvider,
                        groups[index],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _CategoryFilter value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildEmptyCategories() {
    final hasFilter = _filter != _CategoryFilter.all || _query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter ? Icons.filter_alt_off : Icons.category_outlined,
              size: 42,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilter
                  ? 'По этому фильтру ничего нет'
                  : 'Для выбранного периода нет категорий',
              textAlign: TextAlign.center,
            ),
            if (hasFilter) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _filter = _CategoryFilter.all;
                  _query = '';
                }),
                child: const Text('Сбросить фильтр'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    DataProvider dataProvider,
    _CategoryGroup group,
  ) {
    final color = CategoryInfo.getCategoryColor(group.title);
    final selectedOffers = group.offers.where((offer) => offer.isSelected);
    final duplicate = selectedOffers.length > 1;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: color.withValues(alpha: 0.09),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Icon(
                    CategoryInfo.getCategoryIcon(group.title),
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        group.isCovered
                            ? duplicate
                                ? 'Выбрано в ${selectedOffers.length} банках — проверьте дубль'
                                : 'Покрыто · ${_cardLabel(dataProvider, selectedOffers.first.cardId)}'
                            : '${group.offers.length} вариантов · лучший ${_formatPercent(group.bestPercent)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: duplicate
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (group.isCovered)
                  Icon(
                    duplicate
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                    color: duplicate ? Colors.orange : Colors.green,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: group.offers.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
              itemBuilder: (context, index) => _buildOfferRow(
                context,
                dataProvider,
                group,
                group.offers[index],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferRow(
    BuildContext context,
    DataProvider dataProvider,
    _CategoryGroup group,
    CashbackCategoryModel offer,
  ) {
    final isBest = offer.cashbackPercent == group.bestPercent;
    final originalNameDiffers =
        offer.name.trim().toLowerCase() != group.title.trim().toLowerCase();

    return InkWell(
      onLongPress: () => _openCategoryEditor(context, offer),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
        child: Row(
          children: [
            Checkbox(
              value: offer.isSelected,
              onChanged: offer.isSelectionLocked || offer.isTaskBonus
                  ? null
                  : (value) => _toggleCategory(
                        context,
                        dataProvider,
                        offer,
                        value ?? false,
                        group,
                      ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _cardLabel(dataProvider, offer.cardId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: offer.isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (offer.isSelectionLocked) ...[
                        const SizedBox(width: 4),
                        const Tooltip(
                          message: 'Выбор уже закреплён банком',
                          child: Icon(Icons.lock, size: 14),
                        ),
                      ],
                    ],
                  ),
                  if (originalNameDiffers)
                    Text(
                      offer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        isBest
                            ? 'Лучший процент'
                            : 'Есть ${_formatPercent(group.bestPercent)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isBest ? Colors.green : Colors.orange,
                        ),
                      ),
                      CashbackLimitsLabel(
                        maxCashbackAmount: offer.maxCashbackAmount,
                        minPurchaseAmount: offer.minPurchaseAmount,
                        fontSize: 10,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CashbackDescriptionButton(
              categoryName: offer.name,
              description: offer.description,
              iconSize: 17,
            ),
            const SizedBox(width: 4),
            Text(
              '${offer.isStackableBonus ? '+' : ''}${_formatPercent(offer.cashbackPercent)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: offer.isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 17),
              tooltip: 'Редактировать',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openCategoryEditor(context, offer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankView(
    BuildContext context,
    DataProvider dataProvider,
    List<CashbackCategoryModel> periodCategories,
  ) {
    if (dataProvider.cards.isEmpty) {
      return const Center(child: Text('Нет карт для выбора категорий'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: constraints.maxWidth < 600 ? 600 : 430,
            mainAxisExtent: 390,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: dataProvider.cards.length,
          itemBuilder: (context, index) {
            final card = dataProvider.cards[index];
            final cardId = card.id;
            if (cardId == null) {
              return const Card(child: Center(child: Text('Карта без ID')));
            }
            final categories = periodCategories
                .where((category) => category.cardId == cardId)
                .toList()
              ..sort((a, b) {
                if (a.isSelected != b.isSelected) {
                  return a.isSelected ? -1 : 1;
                }
                return b.cashbackPercent.compareTo(a.cashbackPercent);
              });
            return _buildBankCard(
              context,
              dataProvider,
              card,
              categories,
            );
          },
        );
      },
    );
  }

  Widget _buildBankCard(
    BuildContext context,
    DataProvider dataProvider,
    CardModel card,
    List<CashbackCategoryModel> categories,
  ) {
    final cardId = card.id!;
    final maximum = _getMaxCategories(cardId, card.maxCashbackCategories);
    final selected = _selectedStandardCount(categories, cardId);
    final controller = _getMaxController(cardId, maximum);
    final progressColor = selected < maximum
        ? Colors.orange
        : selected == maximum
            ? Colors.green
            : Colors.red;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.credit_card),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cardLabel(dataProvider, cardId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() {
                      _maxCategoriesPerCard[cardId] =
                          int.tryParse(value) ?? _defaultMaxCategories;
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(
                    '$selected/$maximum',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: progressColor,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: categories.isEmpty
                ? const Center(child: Text('Нет категорий'))
                : ListView.separated(
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final groupTitle =
                          normalizedCashbackCategoryName(category.name);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          CategoryInfo.getCategoryIcon(category.name),
                          color: CategoryInfo.getCategoryColor(category.name),
                          size: 19,
                        ),
                        title: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: CashbackLimitsLabel(
                          maxCashbackAmount: category.maxCashbackAmount,
                          minPurchaseAmount: category.minPurchaseAmount,
                          fontSize: 10,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CashbackDescriptionButton(
                              categoryName: category.name,
                              description: category.description,
                              iconSize: 16,
                            ),
                            Text(
                              '${category.isStackableBonus ? '+' : ''}${_formatPercent(category.cashbackPercent)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Checkbox(
                              value: category.isSelected,
                              onChanged: category.isSelectionLocked ||
                                      category.isTaskBonus
                                  ? null
                                  : (value) => _toggleCategory(
                                        context,
                                        dataProvider,
                                        category,
                                        value ?? false,
                                        _CategoryGroup(
                                          title: groupTitle,
                                          offers:
                                              _periodCategories(dataProvider)
                                                  .where(
                                                    (offer) =>
                                                        normalizedCashbackCategoryName(
                                                          offer.name,
                                                        ) ==
                                                        groupTitle,
                                                  )
                                                  .toList(),
                                        ),
                                      ),
                            ),
                          ],
                        ),
                        onLongPress: () =>
                            _openCategoryEditor(context, category),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddCategoriesDialog(context, cardId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить категории'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    DataProvider dataProvider,
    List<CashbackCategoryModel> periodCategories,
    int coveredGroups,
    int totalGroups,
  ) {
    var selected = 0;
    var maximum = 0;
    for (final card in dataProvider.cards) {
      final cardId = card.id;
      if (cardId == null) continue;
      selected += _selectedStandardCount(periodCategories, cardId);
      maximum += _getMaxCategories(cardId, card.maxCashbackCategories);
    }
    final duplicateCount = <String, int>{};
    for (final category in periodCategories.where((item) => item.isSelected)) {
      final title = normalizedCashbackCategoryName(category.name);
      duplicateCount[title] = (duplicateCount[title] ?? 0) + 1;
    }
    final duplicates = duplicateCount.values.where((count) => count > 1).length;

    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: InkWell(
          onTap: () => setState(() => _view = _MonthlyView.banks),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  duplicates > 0 ? Icons.warning_amber_rounded : Icons.task_alt,
                  color: duplicates > 0 ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Покрыто $coveredGroups из $totalGroups категорий',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        duplicates > 0
                            ? 'Мест занято $selected из $maximum · дублей: $duplicates'
                            : 'Мест занято $selected из $maximum',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 430) ...[
                  const Text('План по банкам'),
                  const SizedBox(width: 2),
                ],
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _cardLabel(DataProvider dataProvider, int cardId) {
    final card = dataProvider.getCardById(cardId);
    final suffix =
        card.lastFourDigits == null ? '' : ' · ${card.lastFourDigits}';
    return '${dataProvider.getCardName(cardId)}$suffix';
  }

  String _formatPercent(double value) {
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1).replaceAll('.', ',');
    return '$text%';
  }

  void _showAddCategoriesDialog(BuildContext context, int cardId) {
    final inputController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Добавить категории'),
          content: TextField(
            controller: inputController,
            decoration: const InputDecoration(
              labelText: 'Категории и проценты',
              hintText: '5% Кафе\nРестораны 10%\n7 Такси\nАЗС 5%\n1% Всё',
              helperText:
                  'Одна категория в строке, процент — до или после названия',
              border: OutlineInputBorder(),
            ),
            maxLines: 7,
            minLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                if (inputController.text.trim().isEmpty) return;
                final dataProvider =
                    Provider.of<DataProvider>(context, listen: false);
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                var addedCount = 0;
                final errors = <String>[];

                for (final line in inputController.text.split('\n')) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) continue;
                  try {
                    final parsed = parseCashbackCategoryLine(trimmed);
                    await dataProvider.addCashbackCategoryQuietly(
                      parsed.categoryName,
                      parsed.percent,
                      cardId,
                      _startDate,
                      _getEndOfDay(_endDate),
                      notify: false,
                    );
                    addedCount++;
                  } catch (error) {
                    errors.add('$trimmed: $error');
                  }
                }

                if (!mounted) return;
                navigator.pop();
                if (addedCount > 0) {
                  dataProvider.notifyCashbackCategoriesChanged();
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      errors.isEmpty
                          ? 'Добавлено категорий: $addedCount'
                          : 'Добавлено: $addedCount · ошибок: ${errors.length}',
                    ),
                  ),
                );
                if (errors.isNotEmpty) {
                  debugPrint(
                    'Ошибки добавления категорий:\n${errors.join('\n')}',
                  );
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    ).then((_) {
      Future<void>.delayed(const Duration(seconds: 1), inputController.dispose);
    });
  }
}
