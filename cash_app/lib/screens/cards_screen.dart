import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';

class CardsScreen extends StatelessWidget {
  // Функция для получения цвета категории
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Кино':
        return Colors.orange;
      case 'Кафе':
        return Colors.green;
      case 'Фастфуд':
        return Colors.red;
      case 'Супермаркеты':
        return Colors.blue;
      case 'Транспорт':
        return Colors.purple;
      case 'Одежда':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final cards = dataProvider.cards;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Максимальная ширина плитки (например, 250 пикселей)
        const maxTileWidth = 250.0;
        // Вычисляем количество столбцов
        final crossAxisCount = (constraints.maxWidth / maxTileWidth).floor();
        // Минимум 1 столбец
        final adjustedCrossAxisCount = crossAxisCount > 0 ? crossAxisCount : 1;

        return GridView.count(
          padding: EdgeInsets.all(16.0),
          crossAxisCount: adjustedCrossAxisCount, // Адаптивное количество столбцов
          crossAxisSpacing: 16.0, // Расстояние между колонками
          mainAxisSpacing: 16.0, // Расстояние между строками
          childAspectRatio: 1.0, // Убираем жесткое соотношение сторон
          children: cards.map((card) {
            // Сортировка категорий по убыванию процента кешбека
            final sortedCategories = List.from(card.categories)
              ..sort((a, b) => b.percent.compareTo(a.percent));

            return IntrinsicHeight(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Название карты и номер
                      Text(
                        '${card.name} (**** ${card.number})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      // Список категорий
                      ...sortedCategories.map<Widget>((category) {
                        final categoryColor = _getCategoryColor(category.name);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              Icon(
                                _getCategoryIcon(category.icon), // Получаем иконку
                                size: 16,
                                color: categoryColor,
                              ),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  category.name,
                                  style: TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: categoryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${category.percent}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: categoryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // Функция для получения иконки категории
  IconData _getCategoryIcon(String icon) {
    switch (icon) {
      case 'movie':
        return Icons.movie;
      case 'local_cafe':
        return Icons.local_cafe;
      case 'fastfood':
        return Icons.fastfood;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'directions_bus':
        return Icons.directions_bus;
      case 'shopping_bag':
        return Icons.shopping_bag;
      default:
        return Icons.category;
    }
  }
}