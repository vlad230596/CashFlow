import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../utils/category_info.dart';

class MonthlyCashbackScreen extends StatefulWidget {
  const MonthlyCashbackScreen({super.key});

  @override
  State<MonthlyCashbackScreen> createState() => _MonthlyCashbackScreenState();
}

class _MonthlyCashbackScreenState extends State<MonthlyCashbackScreen> {
  final Map<int, int> _maxCategoriesPerCard = {};
  final Map<int, TextEditingController> _maxCategoriesControllers = {};
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void dispose() {
    _maxCategoriesControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _showMonthPicker(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
    }
  }

  DateTime _getEndDate(DateTime month) {
    return DateTime(month.year, month.month + 1);
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth / 6 - 5; // 6 карт в ряду с отступами

    return Scaffold(
      body: Column(
        children: [
          // Поле выбора месяца
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: InkWell(
              onTap: () => _showMonthPicker(context),
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
                      '${_selectedMonth.month.toString().padLeft(2, '0')}.${_selectedMonth.year}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.calendar_today, size: 20),
                  ],
                ),
              ),
            ),
          ),

          // Список карт в виде плиток
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6, // 6 карт в ряду
                childAspectRatio: 0.7, // Соотношение сторон плитки
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: dataProvider.cards.length,
              itemBuilder: (context, index) {
                final card = dataProvider.cards[index];
                final cardCategories = dataProvider.cashbackCategories
                    .where((c) => c.cardId == card.id)
                    .toList();
                final selectedCount = cardCategories.where((c) => c.isSelected).length;
                _maxCategoriesPerCard[card.id!] = card.maxCashbackCategories!;
                _maxCategoriesControllers.putIfAbsent(
                  card.id!,
                  () => TextEditingController(
                    text: _maxCategoriesPerCard[card.id]?.toString() ?? '3',
                  ),
                );

                Color chipColor;
                if (selectedCount < (_maxCategoriesPerCard[card.id] ?? 3)) {
                  chipColor = Colors.orange;
                } else if (selectedCount == (_maxCategoriesPerCard[card.id] ?? 3)) {
                  chipColor = Colors.green;
                } else {
                  chipColor = Colors.red;
                }

                return Container(
                  // width: cardWidth,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Заголовок карты
                          Text(
                            '${dataProvider.getCardName(card.id!)} ${card.lastFourDigits}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Поле ввода максимума и счётчик
                          Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: TextField(
                                  controller: _maxCategoriesControllers[card.id],
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (value) {
                                    setState(() {
                                      _maxCategoriesPerCard[card.id!] = int.tryParse(value) ?? 3;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Chip(
                                label: Text(
                                  '$selectedCount/${_maxCategoriesPerCard[card.id] ?? 3}',
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
                                ),
                                backgroundColor: chipColor,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Список категорий
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: cardCategories.length,
                              itemBuilder: (context, catIndex) {
                                final category = cardCategories[catIndex];
                                final categoryColor = CategoryInfo.getCategoryColor(category.name);
                                
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CategoryInfo.getCategoryIcon(category.name),
                                        size: 12,
                                        color: categoryColor,
                                      ),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          category.name,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${category.cashbackPercent}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: categoryColor,
                                        ),
                                      ),
                                      Checkbox(
                                        value: category.isSelected,
                                        onChanged: (value) {
                                          Provider.of<DataProvider>(context, listen: false)
                                              .toggleCategorySelection(category.id, value ?? false);
                                        },
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                          // Кнопка добавления
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _showAddCategoriesDialog(context, card.id!),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                minimumSize: Size.zero,
                              ),
                              child: const Text('+', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
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
  final TextEditingController inputController = TextEditingController();
  final endDate = _getEndDate(_selectedMonth);

  showDialog(
    context: context,
    builder: (context) {
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (inputController.text.isEmpty) return;
              
              final lines = inputController.text.split('\n');
              int addedCount = 0;
              final errors = <String>[];
              
              for (final line in lines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty) continue;
                
                try {
                  // Ищем процент в строке (поддерживает форматы: 5%, %5, 5)
                  final percentMatch = RegExp(r'(\d+)\s*%|%\s*(\d+)|\b(\d+)\b').firstMatch(trimmed);
                  if (percentMatch == null) {
                    errors.add('Не найден процент в строке: "$trimmed"');
                    continue;
                  }
                  
                  // Извлекаем числовое значение процента
                  final percentStr = percentMatch.group(1) ?? percentMatch.group(2) ?? percentMatch.group(3);
                  final percent = double.parse(percentStr!);
                  
                  // Извлекаем название категории (удаляем процент из строки)
                  final categoryName = trimmed
                      .replaceAll(percentMatch.group(0)!, '')
                      .trim()
                      .replaceAll(RegExp(r'^\s*[\W_]+|\s*[\W_]+\s*$'), ''); // Удаляем лишние символы по краям
                  
                  if (categoryName.isEmpty) {
                    // Если после удаления процента ничего не осталось, берем всю строку без процента
                    final name = trimmed.replaceAll(RegExp(r'\d+\s*%|%\s*\d+|\b\d+\b'), '').trim();
                    if (name.isEmpty) {
                      errors.add('Не указано название категории в строке: "$trimmed"');
                      continue;
                    }
                    await Provider.of<DataProvider>(context, listen: false).addCashbackCategory(
                      name,
                      percent,
                      cardId,
                      _selectedMonth,
                      endDate,
                    );
                  } else {
                    await Provider.of<DataProvider>(context, listen: false).addCashbackCategory(
                      categoryName,
                      percent,
                      cardId,
                      _selectedMonth,
                      endDate,
                    );
                  }
                  addedCount++;
                } catch (e) {
                  errors.add('Ошибка в строке: "$trimmed" (${e.toString()})');
                }
              }
              
              Navigator.pop(context);
              
              if (errors.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Добавлено $addedCount категорий. Ошибок: ${errors.length}'),
                    duration: const Duration(seconds: 3),
                  ),
                );
                debugPrint('Ошибки при добавлении категорий:\n${errors.join('\n')}');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Успешно добавлено $addedCount категорий')),
                );
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      );
    },
  );
}
}