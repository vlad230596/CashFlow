import 'package:flutter/material.dart';
import '../../utils/category_info.dart';

class CashbackItem extends StatelessWidget {
  final String category;
  final double percent;
  final String cardName;
  final IconData icon;

  const CashbackItem({super.key, 
    required this.category,
    required this.percent,
    required this.cardName,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = CategoryInfo.getCategoryColor(category);

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            // Иконка категории
            Icon(icon, size: 25, color: categoryColor),
            SizedBox(width: 4),
            // Процент кешбека
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              width: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: categoryColor,
                ),
              ),
            ),
            SizedBox(width: 12),
            // Категория и номер карты
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '$cardName',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}