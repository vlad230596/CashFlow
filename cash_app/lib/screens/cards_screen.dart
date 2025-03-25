import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../utils/category_colors.dart'; 
import '../utils/category_icons.dart';

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

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
                        final categoryColor = CategoryColors.getCategoryColor(category.name);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              Icon(
                                CategoryIcons.getCategoryIcon(category.name),
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
                      }),
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
}