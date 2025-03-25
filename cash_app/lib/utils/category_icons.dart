import 'package:flutter/material.dart';

class CategoryIcons {
  static IconData getCategoryIcon(String category) {
    switch (category) {
      case 'Кино':
        return Icons.movie;
      case 'Кафе':
        return Icons.local_cafe;
      case 'Фастфуд':
        return Icons.fastfood;
      case 'Супермаркеты':
        return Icons.shopping_cart;
      case 'Транспорт':
        return Icons.directions_bus;
      case 'Одежда':
        return Icons.shopping_bag;
      default:
        return Icons.category;
    }
  }
}