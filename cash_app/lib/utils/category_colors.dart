import 'package:flutter/material.dart';

class CategoryColors {
  static Color getCategoryColor(String category) {
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
}