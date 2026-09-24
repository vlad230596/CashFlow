import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'plan_confirmation_screen.dart';

import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../services/app_session_type.dart';
import '../services/cashback_import_launcher.dart';
import '../services/cashback_selection_plan.dart';
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
  if (containsAny(['детск', 'для детей', 'игруш', 'малыш'])) {
    return 'Детские товары';
  }
  if (containsAny(['азс', 'топлив', 'заправ'])) return 'АЗС и топливо';
  if (containsAny(['красот', 'космет', 'парфюм', 'бьюти', 'салон', 'спа'])) {
    return 'Красота и уход';
  }
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
  if (containsAny([
    'образован',
    'обучен',
    'курс',
    'школ',
    'университет',
    'репетитор',
    'книг',
  ])) {
    return 'Образование';
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
    case 'Детские товары':
      return 35;
    case 'Аптеки':
      return 40;
    case 'Все покупки':
      return 45;
    case 'АЗС и топливо':
      return 50;
    case 'Красота и уход':
      return 55;
    case 'Общественный транспорт':
      return 60;
    case 'Такси и каршеринг':
      return 65;
    case 'Дом и ремонт':
      return 70;
    case 'Образование':
      return 75;
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

enum _MobileNeedFilter { required, frequent, other }

class _BrowserProfileChoice {
  const _BrowserProfileChoice({required this.profile, this.userId});

  final CashbackImportProfile profile;
  final int? userId;
}

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
  const MonthlyCashbackScreen({
    super.key,
    this.onShellDestinationSelected,
  });

  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<MonthlyCashbackScreen> createState() => _MonthlyCashbackScreenState();
}

class _MonthlyCashbackScreenState extends State<MonthlyCashbackScreen> {
  static const int _defaultMaxCategories = 3;

  final Map<int, int> _maxCategoriesPerCard = {};
  final Map<int, TextEditingController> _maxCategoriesControllers = {};
  final Set<int> _rejectedCategoryIds = {};
  late DateTime _startDate;
  late DateTime _endDate;
  _MonthlyView _view = _MonthlyView.categories;
  _CategoryFilter _filter = _CategoryFilter.all;
  _MobileNeedFilter _mobileNeedFilter = _MobileNeedFilter.required;
  String? _mobileEditingGroupTitle;
  int? _mobileSelectedOfferId;
  bool _mobileReviewingPlan = false;
  String _query = '';
  bool _sendingToChrome = false;

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

  String _formatMonth(DateTime date) {
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return '${months[date.month - 1]} ${date.year}';
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
        final aRejected = _rejectedCategoryIds.contains(a.id);
        final bRejected = _rejectedCategoryIds.contains(b.id);
        if (aRejected != bRejected) return aRejected ? 1 : -1;
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
      if (mounted) {
        setState(() => _rejectedCategoryIds.remove(category.id));
      }
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

  Future<void> _toggleCategoryRejection(
    BuildContext context,
    DataProvider dataProvider,
    CashbackCategoryModel category,
  ) async {
    if (category.isSelectionLocked || category.isTaskBonus) return;
    final reject = !_rejectedCategoryIds.contains(category.id);
    setState(() {
      if (reject) {
        _rejectedCategoryIds.add(category.id);
      } else {
        _rejectedCategoryIds.remove(category.id);
      }
    });
    if (!reject) return;

    try {
      if (category.isSelected) {
        await dataProvider.toggleCategorySelection(category.id, false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _rejectedCategoryIds.remove(category.id));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось исключить категорию')),
      );
    }
  }

  Future<_BrowserProfileChoice?> _selectBrowserProfile(
    BuildContext context,
    DataProvider dataProvider,
  ) {
    final orderedUsers = [...dataProvider.users]
      ..sort((a, b) => a.id.compareTo(b.id));
    return showDialog<_BrowserProfileChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Куда передать план?'),
        children: [
          for (final profile in cashbackImportProfiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                dialogContext,
                _BrowserProfileChoice(
                  profile: profile,
                  userId: profile.userSlot < orderedUsers.length
                      ? orderedUsers[profile.userSlot].id
                      : null,
                ),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(
                  profile.userSlot < orderedUsers.length
                      ? orderedUsers[profile.userSlot].name
                      : profile.label,
                ),
                subtitle: Text(profile.label),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendTodayPlanToChrome(
    BuildContext context,
    DataProvider dataProvider,
  ) async {
    final target = await _selectBrowserProfile(context, dataProvider);
    if (target == null || !context.mounted) return;
    final profile = target.profile;

    final plan = buildCashbackSelectionPlan(
      now: DateTime.now(),
      banks: dataProvider.banks,
      users: dataProvider.users,
      cards: dataProvider.cards,
      categories: dataProvider.cashbackCategories,
      requestedBankIds: profile.banks,
      userId: target.userId,
    );
    final planBanks = plan['banks'] as List<dynamic>;
    if (planBanks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'На сегодня нет категорий для поддерживаемых банков.',
          ),
        ),
      );
      return;
    }

    setState(() => _sendingToChrome = true);
    String? error;
    try {
      error = await launchCashbackImport(
        profile,
        selectionPlan: jsonEncode(plan),
      );
    } catch (exception) {
      error = 'Не удалось передать план в Chrome: $exception';
    }
    if (!context.mounted) return;
    setState(() => _sendingToChrome = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'План на сегодня передан в Chrome. Справа открыт чек-лист без автоматических кликов.',
        ),
      ),
    );
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Scaffold(
          body: compact
              ? SafeArea(
                  bottom: false,
                  child: _buildMobilePlan(
                    context,
                    dataProvider,
                    visibleGroups,
                  ),
                )
              : Column(
                  children: [
                    _buildHeader(context, dataProvider),
                    Expanded(
                      child: _view == _MonthlyView.categories
                          ? _buildCategoryView(
                              context,
                              dataProvider,
                              visibleGroups,
                            )
                          : _buildBankView(
                              context,
                              dataProvider,
                              periodCategories,
                            ),
                    ),
                  ],
                ),
          bottomNavigationBar: compact
              ? null
              : _buildSummary(
                  context,
                  dataProvider,
                  periodCategories,
                  coveredGroups,
                  totalGroups,
                ),
        );
      },
    );
  }

  Widget _buildMobilePlan(
    BuildContext context,
    DataProvider dataProvider,
    List<_CategoryGroup> allGroups,
  ) {
    final requiredGroups = allGroups
        .where((group) => cashbackCategorySortPriority(group.title) <= 50)
        .toList();
    final groups = allGroups.where((group) {
      final priority = cashbackCategorySortPriority(group.title);
      return switch (_mobileNeedFilter) {
        _MobileNeedFilter.required => priority <= 50,
        _MobileNeedFilter.frequent => priority > 50 && priority <= 80,
        _MobileNeedFilter.other => priority > 80,
      };
    }).toList()
      ..sort((a, b) {
        if (a.isCovered != b.isCovered) return a.isCovered ? 1 : -1;
        return cashbackCategorySortPriority(
          a.title,
        ).compareTo(cashbackCategorySortPriority(b.title));
      });
    final coveredRequired =
        requiredGroups.where((group) => group.isCovered).length;
    final familyNames =
        dataProvider.users.take(2).map((user) => user.name).join(' и ');
    final editingGroup = _mobileEditingGroupTitle == null
        ? null
        : allGroups
            .where((group) => group.title == _mobileEditingGroupTitle)
            .firstOrNull;

    if (_mobileReviewingPlan) {
      return _buildMobilePlanReview(context, dataProvider, allGroups);
    }

    if (editingGroup != null) {
      return _buildMobileCardSelector(
        context,
        dataProvider,
        editingGroup,
      );
    }

    return KeyedSubtree(
      key: const ValueKey('mobile-plan-overview'),
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE7EBF0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    familyNames.isEmpty
                        ? 'Семейный план'
                        : 'Семья · $familyNames',
                    style: const TextStyle(
                      color: Color(0xFF637189),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'План',
                          style: TextStyle(
                            color: Color(0xFF0D2852),
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _showDateRangePicker(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: const Color(0xFFEDF2F8),
                          foregroundColor: const Color(0xFF425A78),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(_formatMonth(_startDate)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              children: [
                _buildMobileGuide(coveredRequired, requiredGroups.length),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMobileFilterChip(
                        'Обязательные',
                        _MobileNeedFilter.required,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMobileFilterChip(
                        'Частые',
                        _MobileNeedFilter.frequent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMobileFilterChip(
                        'Остальные',
                        _MobileNeedFilter.other,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (groups.isEmpty)
                  _buildMobileEmptyNeeds()
                else
                  for (var index = 0; index < groups.length; index++) ...[
                    _buildMobileNeedCard(
                      context,
                      dataProvider,
                      groups[index],
                      expanded: !groups[index].isCovered &&
                          groups.take(index).every((group) => group.isCovered),
                    ),
                    const SizedBox(height: 8),
                  ],
                if (allGroups.any((group) => group.isCovered)) ...[
                  FilledButton(
                    onPressed: () => setState(() {
                      _mobileReviewingPlan = true;
                    }),
                    child: const Text('Проверить план'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: dataProvider.cards.isEmpty
                      ? null
                      : () => _showAddCategoriesDialog(
                            context,
                            dataProvider.cards.first.id!,
                          ),
                  child: const Text('Добавить потребность'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePlanReview(
    BuildContext context,
    DataProvider dataProvider,
    List<_CategoryGroup> allGroups,
  ) {
    final periodCategories = _periodCategories(dataProvider)
        .where((category) => category.isSelectable)
        .toList();
    final required = allGroups
        .where((group) => cashbackCategorySortPriority(group.title) <= 50)
        .toList();
    final frequent = allGroups.where((group) {
      final priority = cashbackCategorySortPriority(group.title);
      return priority > 50 && priority <= 80;
    }).toList();
    final occupied = periodCategories.where((category) => category.isSelected);
    final totalSlots = dataProvider.cards.fold<int>(
      0,
      (sum, card) =>
          sum + _getMaxCategories(card.id!, card.maxCashbackCategories),
    );
    final familyNames =
        dataProvider.users.take(2).map((user) => user.name).join(' и ');
    final cards = dataProvider.cards.where((card) {
      return periodCategories.any(
        (category) => category.cardId == card.id && category.isSelected,
      );
    }).toList()
      ..sort((a, b) => a.id!.compareTo(b.id!));
    final uncovered = allGroups.where((group) => !group.isCovered).firstOrNull;
    final freeCards = dataProvider.cards.where((card) {
      final maximum = _getMaxCategories(card.id!, card.maxCashbackCategories);
      return _selectedStandardCount(periodCategories, card.id!) < maximum;
    }).length;

    return KeyedSubtree(
      key: const ValueKey('mobile-plan-review'),
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE7EBF0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    familyNames.isEmpty
                        ? 'Семейный план'
                        : 'Семья · $familyNames',
                    style: const TextStyle(
                      color: Color(0xFF637189),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'План',
                          style: TextStyle(
                            color: Color(0xFF0D2852),
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() {
                          _mobileReviewingPlan = false;
                        }),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: const Color(0xFFEDF2F8),
                          foregroundColor: const Color(0xFF425A78),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(_formatMonth(_startDate)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              children: [
                Container(
                  constraints: const BoxConstraints(minHeight: 124),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14366E), Color(0xFF2972D1)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'План заполнен вручную',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Можно менять назначения в любом порядке',
                        style: TextStyle(color: Color(0xFFD8E7FF), fontSize: 9),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _mobileReviewStat(
                              '${required.where((group) => group.isCovered).length}/${required.length}',
                              'обязательных',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _mobileReviewStat(
                              '${frequent.where((group) => group.isCovered).length}/${frequent.length}',
                              'частых',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _mobileReviewStat(
                              '${occupied.length}/$totalSlots',
                              'мест занято',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                for (final card in cards) ...[
                  _buildMobilePlanCard(dataProvider, periodCategories, card),
                  const SizedBox(height: 8),
                ],
                if (uncovered != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3DF),
                      borderRadius: BorderRadius.circular(7),
                      border: const Border(
                        left: BorderSide(color: Color(0xFFDB7A00), width: 3),
                      ),
                    ),
                    child: Text(
                      'Не закрыто: ${_mobileNeedTitle(uncovered.title)} · ${_mobileNeedKind(uncovered.title)}. Свободные места есть в ${_mobileCardsCount(freeCards)}.',
                      style: const TextStyle(
                        color: Color(0xFF80500F),
                        fontSize: 9,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlanConfirmationScreen(
                        onShellDestinationSelected:
                            widget.onShellDestinationSelected,
                      ),
                    ),
                  ),
                  child: const Text('Перейти к подтверждению'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileReviewStat(String value, String label) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(color: Color(0xFFD8E7FF), fontSize: 8),
            ),
          ],
        ),
      );

  Widget _buildMobilePlanCard(
    DataProvider dataProvider,
    List<CashbackCategoryModel> periodCategories,
    CardModel card,
  ) {
    final categories = periodCategories
        .where((category) => category.cardId == card.id && category.isSelected)
        .toList();
    final maximum = _getMaxCategories(card.id!, card.maxCashbackCategories);
    final bankName = _mobileBankName(dataProvider, card.id!);
    final owner = dataProvider.users
            .where((user) => user.id == card.userId)
            .map((user) => user.name)
            .firstOrNull ??
        'Владелец';
    final normalizedBank = bankName.toLowerCase();
    final (logo, logoColor) = normalizedBank.contains('втб')
        ? ('ВТБ', const Color(0xFF1682BA))
        : normalizedBank.contains('т-банк') || normalizedBank.contains('тинь')
            ? ('Т', const Color(0xFF171717))
            : ('A', const Color(0xFF17386B));
    final full = categories.length >= maximum;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDFE6EE)),
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFFF0F4F8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: logoColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    logo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mobileCardLabel(dataProvider, card.id!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF17243B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        owner,
                        style: const TextStyle(
                          color: Color(0xFF69778D),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: full
                        ? const Color(0xFF168154)
                        : const Color(0xFFE3E9F1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${categories.length} / $maximum',
                    style: TextStyle(
                      color: full ? Colors.white : const Color(0xFF51647D),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final category in categories)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFEDF1F5)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: ExcludeSemantics(
                      child: Icon(
                        _mobileCategoryIcon(category.name),
                        size: 14,
                        color: const Color(0xFF1B6FF3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _mobileNeedTitle(category.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17243B),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Text(
                    _formatPercent(category.cashbackPercent),
                    style: const TextStyle(
                      color: Color(0xFFDB7A00),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _mobileNeedKind(String title) {
    final priority = cashbackCategorySortPriority(title);
    if (priority <= 50) return 'обязательная потребность';
    if (priority <= 80) return 'частая потребность';
    return 'остальная потребность';
  }

  String _mobileCardsCount(int count) => switch (count) {
        1 => 'одной карте',
        2 => 'двух картах',
        _ => '$count картах',
      };

  IconData _mobileCategoryIcon(String title) {
    return switch (normalizedCashbackCategoryName(title)) {
      'Продукты и супермаркеты' => Icons.shopping_cart_outlined,
      'Путешествия' => Icons.flight_outlined,
      'АЗС и топливо' => Icons.local_gas_station_outlined,
      'Кафе и рестораны' => Icons.restaurant_outlined,
      'Одежда и обувь' => Icons.checkroom_outlined,
      'Аптеки' => Icons.local_pharmacy_outlined,
      'Дом и ремонт' => Icons.handyman_outlined,
      'Такси и каршеринг' => Icons.local_taxi_outlined,
      _ => Icons.category_outlined,
    };
  }

  Widget _buildMobileGuide(int covered, int total) {
    final progress = total == 0 ? 0.0 : covered / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF15386F), Color(0xFF2770CE)],
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Обязательные потребности',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$covered из $total',
                style: const TextStyle(
                  color: Color(0xFFD8E7FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF5578A7),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterChip(String label, _MobileNeedFilter value) {
    final selected = _mobileNeedFilter == value;
    return Material(
      color: selected ? const Color(0xFFEAF2FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: selected ? const Color(0xFF1B6FF3) : const Color(0xFFDFE6EE),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _mobileNeedFilter = value),
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1B6FF3)
                    : const Color(0xFF4F6078),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileEmptyNeeds() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDFE6EE)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Text(
          'Здесь пока нет потребностей',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF69778D)),
        ),
      );

  Widget _buildMobileNeedCard(
    BuildContext context,
    DataProvider dataProvider,
    _CategoryGroup group, {
    required bool expanded,
  }) {
    final selectedOffer =
        group.offers.where((offer) => offer.isSelected).firstOrNull;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: expanded ? const Color(0xFF1B6FF3) : const Color(0xFFDFE6EE),
          width: expanded ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    group.isCovered ? Icons.check_rounded : Icons.add_rounded,
                    color: const Color(0xFF1B6FF3),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mobileNeedTitle(group.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF17243B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedOffer == null
                            ? 'Ещё не назначено'
                            : _mobileCardLabel(
                                dataProvider,
                                selectedOffer.cardId,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF69778D),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: group.isCovered
                        ? const Color(0xFFE8F6EE)
                        : const Color(0xFFFFF3DF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    selectedOffer == null
                        ? 'Важно'
                        : _formatPercent(selectedOffer.cashbackPercent),
                    style: TextStyle(
                      color: group.isCovered
                          ? const Color(0xFF168154)
                          : const Color(0xFF9B5700),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, indent: 10, endIndent: 10),
            for (final offer in group.offers.take(3))
              _buildMobileOffer(context, dataProvider, group, offer),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileOffer(
    BuildContext context,
    DataProvider dataProvider,
    _CategoryGroup group,
    CashbackCategoryModel offer,
  ) {
    final card = dataProvider.getCardById(offer.cardId);
    final bankName = dataProvider.banks
            .where((bank) => bank.id == card.bankId)
            .map((bank) => bank.name)
            .firstOrNull ??
        dataProvider.getCardName(offer.cardId);
    final normalizedBank = bankName.toLowerCase();
    final (logo, logoColor) = normalizedBank.contains('втб')
        ? ('ВТБ', const Color(0xFF1682BA))
        : normalizedBank.contains('т-банк') || normalizedBank.contains('тинь')
            ? ('Т', const Color(0xFF171717))
            : ('A', const Color(0xFF17386B));
    return InkWell(
      onTap: offer.isSelectionLocked || offer.isTaskBonus
          ? null
          : () => setState(() {
                _mobileEditingGroupTitle = group.title;
                _mobileSelectedOfferId = offer.id;
              }),
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              Container(
                width: 138,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: logoColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  logo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '$bankName${card.lastFourDigits == null ? '' : ' · ${card.lastFourDigits}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17243B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatPercent(offer.cashbackPercent),
                style: const TextStyle(
                  color: Color(0xFFDB7A00),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCardSelector(
    BuildContext context,
    DataProvider dataProvider,
    _CategoryGroup group,
  ) {
    final selected = group.offers
        .where((offer) => offer.id == _mobileSelectedOfferId)
        .firstOrNull;
    final selectedCard =
        selected == null ? null : dataProvider.getCardById(selected.cardId);
    final selectedMaximum = selectedCard == null
        ? 0
        : _getMaxCategories(
            selected!.cardId,
            selectedCard.maxCashbackCategories,
          );
    final selectedUsed = selected == null
        ? 0
        : _selectedStandardCount(
            _periodCategories(dataProvider),
            selected.cardId,
          );
    final filteredGroups = _categoryGroups(dataProvider).where((candidate) {
      final priority = cashbackCategorySortPriority(candidate.title);
      return switch (_mobileNeedFilter) {
        _MobileNeedFilter.required => priority <= 50,
        _MobileNeedFilter.frequent => priority > 50 && priority <= 80,
        _MobileNeedFilter.other => priority > 80,
      };
    }).toList();
    final coveredAfterAssignment =
        filteredGroups.where((candidate) => candidate.isCovered).length +
            (group.isCovered ? 0 : 1);
    final needLabel = switch (_mobileNeedFilter) {
      _MobileNeedFilter.required => 'обязательные',
      _MobileNeedFilter.frequent => 'частые',
      _MobileNeedFilter.other => 'остальные',
    };
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE7EBF0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'План · Обязательные',
                  style: TextStyle(
                    color: Color(0xFF637189),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _mobileNeedTitle(group.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0D2852),
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _mobileEditingGroupTitle = null;
                        _mobileSelectedOfferId = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: const Color(0xFFEDF2F8),
                        foregroundColor: const Color(0xFF425A78),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Назад',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
            children: [
              const Text(
                'Выберите карту',
                style: TextStyle(
                  color: Color(0xFF0D2852),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Проценты, свободные места и известные ограничения показаны рядом. Решение остаётся за вами.',
                style: TextStyle(
                  color: Color(0xFF69778D),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              for (final offer in group.offers) ...[
                _buildMobileCardOption(
                  dataProvider,
                  offer,
                  selected: offer.id == _mobileSelectedOfferId,
                  onTap: () => setState(() {
                    _mobileSelectedOfferId = offer.id;
                  }),
                ),
                const SizedBox(height: 8),
              ],
              if (selected != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6EE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'После назначения: $needLabel $coveredAfterAssignment из ${filteredGroups.length} · ${_mobileBankName(dataProvider, selected.cardId)} будет заполнена ${selectedUsed + 1} из $selectedMaximum.',
                    style: const TextStyle(
                      color: Color(0xFF23553E),
                      fontSize: 9,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        await _toggleCategory(
                          context,
                          dataProvider,
                          selected,
                          true,
                          group,
                        );
                        if (!mounted) return;
                        setState(() {
                          _mobileEditingGroupTitle = null;
                          _mobileSelectedOfferId = null;
                        });
                      },
                child: Text(
                  selected == null
                      ? 'Выберите карту'
                      : 'Назначить ${_mobileBankName(dataProvider, selected.cardId)}',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _mobileEditingGroupTitle = null;
                  _mobileSelectedOfferId = null;
                }),
                child: const Text('Оставить без карты'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCardOption(
    DataProvider dataProvider,
    CashbackCategoryModel offer, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final card = dataProvider.getCardById(offer.cardId);
    final maximum = _getMaxCategories(
      offer.cardId,
      card.maxCashbackCategories,
    );
    final used = _selectedStandardCount(
      _periodCategories(dataProvider),
      offer.cardId,
    );
    final owner = dataProvider.users
            .where((user) => user.id == card.userId)
            .map((user) => user.name)
            .firstOrNull ??
        'Владелец';
    final bankName = _mobileBankName(dataProvider, offer.cardId);
    final normalizedBank = bankName.toLowerCase();
    final (logo, logoColor) = normalizedBank.contains('втб')
        ? ('ВТБ', const Color(0xFF1682BA))
        : normalizedBank.contains('т-банк') || normalizedBank.contains('тинь')
            ? ('Т', const Color(0xFF171717))
            : ('A', const Color(0xFF17386B));

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected ? const Color(0xFF1B6FF3) : const Color(0xFFDFE6EE),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF1B6FF3)
                            : const Color(0xFFB7C3D2),
                        width: selected ? 6 : 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: logoColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      logo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _mobileCardLabel(dataProvider, offer.cardId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF17243B),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '$owner · осталось ${maximum - used} из $maximum мест',
                          style: const TextStyle(
                            color: Color(0xFF69778D),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatPercent(offer.cashbackPercent),
                    style: const TextStyle(
                      color: Color(0xFFDB7A00),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (offer.maxCashbackAmount != null ||
                  offer.minPurchaseAmount != null) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (offer.maxCashbackAmount != null)
                      _mobileFact(
                        'до ${_mobileInteger(offer.maxCashbackAmount!)} ₽ возврата',
                      ),
                    if (offer.minPurchaseAmount != null)
                      _mobileFact(
                        'от ${_mobileInteger(offer.minPurchaseAmount!)} ₽',
                        warning: true,
                      ),
                    if (offer.description?.trim().isNotEmpty == true)
                      _mobileFact(offer.description!.trim().toLowerCase()),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileFact(String text, {bool warning = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: warning ? const Color(0xFFFFF3DF) : const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: warning ? const Color(0xFF8D5000) : const Color(0xFF5E6C80),
            fontSize: 9,
          ),
        ),
      );

  String _mobileInteger(double value) {
    final digits = value.toStringAsFixed(0);
    return digits.replaceAllMapped(
      RegExp(r'(?<!^)(?=(\d{3})+$)'),
      (_) => ' ',
    );
  }

  String _mobileBankName(DataProvider dataProvider, int cardId) {
    final card = dataProvider.getCardById(cardId);
    return dataProvider.banks
            .where((bank) => bank.id == card.bankId)
            .map((bank) => bank.name)
            .firstOrNull ??
        dataProvider.getCardName(cardId);
  }

  String _mobileCardLabel(DataProvider dataProvider, int cardId) {
    final card = dataProvider.getCardById(cardId);
    final bankName = dataProvider.banks
            .where((bank) => bank.id == card.bankId)
            .map((bank) => bank.name)
            .firstOrNull ??
        dataProvider.getCardName(cardId);
    return '$bankName${card.lastFourDigits == null ? '' : ' · ${card.lastFourDigits}'}';
  }

  String _mobileNeedTitle(String title) => switch (title) {
        'Продукты и супермаркеты' => 'Супермаркеты',
        'Кафе и рестораны' => 'Кафе',
        'АЗС и топливо' => 'АЗС',
        'Такси и каршеринг' => 'Такси',
        _ => title,
      };

  Widget _buildHeader(BuildContext context, DataProvider dataProvider) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
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
            final sendButton = FilledButton.icon(
              onPressed: _sendingToChrome
                  ? null
                  : () => _sendTodayPlanToChrome(context, dataProvider),
              icon: _sendingToChrome
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_browser, size: 18),
              label: Text(
                _sendingToChrome ? 'Передаём…' : 'Показать в Chrome',
              ),
            );
            final canSendToChrome =
                detectAppSessionType().canLaunchCashbackBrowser;
            final confirmationButton = OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlanConfirmationScreen(
                    onShellDestinationSelected:
                        widget.onShellDestinationSelected,
                  ),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Подтверждение в банках'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'План',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _showDateRangePicker(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text(_formatMonth(_startDate)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  switcher,
                  const SizedBox(height: 8),
                  confirmationButton,
                  if (canSendToChrome) ...[
                    const SizedBox(height: 8),
                    sendButton,
                  ],
                ],
              );
            }
            return Row(
              children: [
                dateButton,
                const Spacer(),
                switcher,
                const SizedBox(width: 8),
                confirmationButton,
                if (canSendToChrome) ...[
                  const SizedBox(width: 8),
                  sendButton,
                ],
              ],
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
    final isRejected = _rejectedCategoryIds.contains(offer.id);

    return InkWell(
      onLongPress: () => _openCategoryEditor(context, offer),
      child: Ink(
        color: isRejected
            ? Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.35)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
          child: Row(
            children: [
              _buildDecisionControls(
                context,
                dataProvider,
                offer,
                group,
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
                    if (offer.isSelected)
                      Text(
                        offer.isBankConfirmed
                            ? 'Подтверждено банком'
                            : 'Ожидает подтверждения банка',
                        style: TextStyle(
                          fontSize: 11,
                          color: offer.isBankConfirmed
                              ? Colors.green
                              : Colors.orange,
                        ),
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
                        if (isRejected)
                          Text(
                            'Исключено',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.error,
                            ),
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
      ),
    );
  }

  Widget _buildDecisionControls(
    BuildContext context,
    DataProvider dataProvider,
    CashbackCategoryModel category,
    _CategoryGroup? group,
  ) {
    final disabled = category.isSelectionLocked || category.isTaskBonus;
    final rejected = _rejectedCategoryIds.contains(category.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 32, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: category.isSelected ? 'Снять выбор' : 'Выбрать',
          onPressed: disabled
              ? null
              : () => _toggleCategory(
                    context,
                    dataProvider,
                    category,
                    !category.isSelected,
                    group,
                  ),
          icon: Icon(
            category.isSelected
                ? Icons.check_circle
                : Icons.check_circle_outline,
            color: category.isSelected ? Colors.green : null,
            size: 22,
          ),
        ),
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 32, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: rejected ? 'Вернуть в рассмотрение' : 'Исключить',
          onPressed: disabled
              ? null
              : () => _toggleCategoryRejection(
                    context,
                    dataProvider,
                    category,
                  ),
          icon: Icon(
            rejected ? Icons.cancel : Icons.cancel_outlined,
            color: rejected ? Theme.of(context).colorScheme.error : null,
            size: 22,
          ),
        ),
      ],
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
                final aRejected = _rejectedCategoryIds.contains(a.id);
                final bRejected = _rejectedCategoryIds.contains(b.id);
                if (aRejected != bRejected) return aRejected ? 1 : -1;
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CashbackLimitsLabel(
                              maxCashbackAmount: category.maxCashbackAmount,
                              minPurchaseAmount: category.minPurchaseAmount,
                              fontSize: 10,
                            ),
                            if (_rejectedCategoryIds.contains(category.id))
                              Text(
                                'Исключено из плана',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
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
                            _buildDecisionControls(
                              context,
                              dataProvider,
                              category,
                              _CategoryGroup(
                                title: groupTitle,
                                offers: _periodCategories(dataProvider)
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
