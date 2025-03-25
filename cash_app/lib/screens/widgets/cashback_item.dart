import 'package:flutter/material.dart';
import '../../utils/category_colors.dart';

class CashbackItem extends StatelessWidget {
  final String category;
  final double percent;
  final String cardNumber;
  final IconData icon;

  const CashbackItem({super.key, 
    required this.category,
    required this.percent,
    required this.cardNumber,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = CategoryColors.getCategoryColor(category);

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Иконка категории
            Icon(icon, size: 40, color: categoryColor),
            SizedBox(width: 12),
            // Процент кешбека
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 16,
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Карта: **** $cardNumber',
                    style: TextStyle(
                      fontSize: 14,
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