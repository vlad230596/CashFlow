import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../utils/category_info.dart';
import 'cashback_category_edit_screen.dart';

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
      lastDate: DateTime(2030),
    );

    if (picked != null) {
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

  bool _isCategoryInSelectedPeriod(DateTime startDate, DateTime endDate) {
    final categoryStart = DateUtils.dateOnly(startDate);
    final categoryEnd = DateUtils.dateOnly(endDate);

    return !categoryEnd.isBefore(_startDate) &&
        !categoryStart.isAfter(_endDate);
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

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: InkWell(
              onTap: () => _showDateRangePicker(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.calendar_today, size: 20),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: 340,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: dataProvider.cards.length,
              itemBuilder: (context, index) {
                final card = dataProvider.cards[index];
                final cardId = card.id;
                final cardCategories = dataProvider.cashbackCategories
                    .where((category) => category.cardId == cardId)
                    .where(
                      (category) => _isCategoryInSelectedPeriod(
                        category.startDate,
                        category.endDate,
                      ),
                    )
                    .toList();
                final selectedCount = cardCategories
                    .where((category) => category.isSelected)
                    .length;

                if (cardId == null) {
                  return const Card(
                    child: Center(child: Text('Карта без ID')),
                  );
                }

                final maxCategories =
                    _getMaxCategories(cardId, card.maxCashbackCategories);
                final maxController = _getMaxController(cardId, maxCategories);
                final chipColor = selectedCount < maxCategories
                    ? Colors.orange
                    : selectedCount == maxCategories
                        ? Colors.green
                        : Colors.red;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dataProvider.getCardName(cardId)} ${card.lastFourDigits ?? '????'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: TextField(
                                controller: maxController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (value) {
                                  setState(() {
                                    _maxCategoriesPerCard[cardId] =
                                        int.tryParse(value) ??
                                            _defaultMaxCategories;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(
                                '$selectedCount/$maxCategories',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: chipColor,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: cardCategories.length,
                            itemBuilder: (context, catIndex) {
                              final category = cardCategories[catIndex];
                              final categoryColor =
                                  CategoryInfo.getCategoryColor(category.name);

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onLongPress: () =>
                                      _openCategoryEditor(context, category),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CategoryInfo.getCategoryIcon(
                                            category.name),
                                        size: 12,
                                        color: categoryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          category.name,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${category.cashbackPercent}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: categoryColor,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16),
                                        tooltip: 'Редактировать',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minHeight: 28,
                                          minWidth: 28,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _openCategoryEditor(
                                          context,
                                          category,
                                        ),
                                      ),
                                      Checkbox(
                                        value: category.isSelected,
                                        onChanged: (value) {
                                          Provider.of<DataProvider>(
                                            context,
                                            listen: false,
                                          ).toggleCategorySelection(
                                            category.id,
                                            value ?? false,
                                          );
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () =>
                                _showAddCategoriesDialog(context, cardId),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            child:
                                const Text('+', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoriesDialog(BuildContext context, int cardId) {
    final inputController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Добавить категории'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inputController,
                decoration: const InputDecoration(
                  labelText: 'Введите категории и проценты',
                  hintText: '5% Кафе\nРестораны 10%\n7 Такси\nАЗС 5%\n1% Всё',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                minLines: 3,
              ),
              const SizedBox(height: 8),
              const Text(
                'Формат: процент и название в любом порядке (5% Категория или Категория 5%)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (inputController.text.isEmpty) return;

                final dataProvider =
                    Provider.of<DataProvider>(context, listen: false);
                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                final lines = inputController.text.split('\n');
                var addedCount = 0;
                final errors = <String>[];

                for (final line in lines) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) continue;

                  try {
                    final percentMatch =
                        RegExp(r'(\d+)\s*%|%\s*(\d+)|\b(\d+)\b')
                            .firstMatch(trimmed);
                    if (percentMatch == null) {
                      errors.add('Не найден процент в строке: "$trimmed"');
                      continue;
                    }

                    final percentStr = percentMatch.group(1) ??
                        percentMatch.group(2) ??
                        percentMatch.group(3);
                    final percent = double.parse(percentStr!);
                    final categoryName = trimmed
                        .replaceAll(percentMatch.group(0)!, '')
                        .trim()
                        .replaceAll(RegExp(r'^\s*[\W_]+|\s*[\W_]+\s*$'), '');

                    if (categoryName.isEmpty) {
                      errors.add(
                        'Не указано название категории в строке: "$trimmed"',
                      );
                      continue;
                    }

                    await dataProvider.addCashbackCategory(
                      categoryName,
                      percent,
                      cardId,
                      _startDate,
                      _getEndOfDay(_endDate),
                    );
                    addedCount++;
                  } catch (e) {
                    errors.add('Ошибка в строке: "$trimmed" (${e.toString()})');
                  }
                }

                if (!mounted) return;
                navigator.pop();

                if (errors.isNotEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Добавлено категорий: $addedCount. Ошибок: ${errors.length}',
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  debugPrint(
                    'Ошибки при добавлении категорий:\n${errors.join('\n')}',
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Успешно добавлено категорий: $addedCount'),
                    ),
                  );
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    ).then((_) => inputController.dispose());
  }
}
