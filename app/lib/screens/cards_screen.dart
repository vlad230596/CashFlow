import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/data_provider.dart';
import '../utils/category_info.dart';
import 'widgets/cashback_description_button.dart';
import 'widgets/cashback_limits_label.dart';

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final cashbackCategories = dataProvider.effectiveActiveCashbackCategories;

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxTileWidth = 250.0;
        final crossAxisCount = (constraints.maxWidth / maxTileWidth).floor();
        final adjustedCrossAxisCount = crossAxisCount > 0 ? crossAxisCount : 1;

        return GridView.count(
          padding: const EdgeInsets.all(16.0),
          crossAxisCount: adjustedCrossAxisCount,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 1.0,
          children: dataProvider.cards.map((card) {
            final sortedCategories = cashbackCategories
                .where((category) => category.cardId == card.id)
                .toList();

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
                      Text(
                        '${dataProvider.getCardName(card.id ?? -1)} '
                        '${card.lastFourDigits ?? '????'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...sortedCategories.map<Widget>((category) {
                        final categoryColor =
                            CategoryInfo.getCategoryColor(category.name);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              Icon(
                                CategoryInfo.getCategoryIcon(category.name),
                                size: 16,
                                color: categoryColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category.name,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    CashbackLimitsLabel(
                                      maxCashbackAmount:
                                          category.maxCashbackAmount,
                                      minPurchaseAmount:
                                          category.minPurchaseAmount,
                                    ),
                                  ],
                                ),
                              ),
                              CashbackDescriptionButton(
                                categoryName: category.name,
                                description: category.description,
                                iconSize: 14,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: categoryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${category.isStackableBonus ? '+' : ''}${category.cashbackPercent}%',
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
