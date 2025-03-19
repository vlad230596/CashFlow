import 'package:flutter/material.dart';

class DataProvider with ChangeNotifier {
  // Данные о картах
  final List<Map<String, dynamic>> _cards = [
    {
      'name': 'Карта 1',
      'number': '1234',
      'categories': [
        {'name': 'Кино', 'percent': 5, 'icon': Icons.movie},
        {'name': 'Кафе', 'percent': 7, 'icon': Icons.local_cafe},
        {'name': 'Фастфуд', 'percent': 4, 'icon': Icons.fastfood},
      ],
    },
    {
      'name': 'Карта 2',
      'number': '5678',
      'categories': [
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
        {'name': 'Транспорт', 'percent': 6, 'icon': Icons.directions_bus},
        {'name': 'Одежда', 'percent': 5, 'icon': Icons.shopping_bag},
      ],
    },
    {
      'name': 'Карта 3',
      'number': '9876',
      'categories': [
        {'name': 'Кино', 'percent': 6, 'icon': Icons.movie},
        {'name': 'Кафе', 'percent': 4, 'icon': Icons.local_cafe},
        {'name': 'Фастфуд', 'percent': 5, 'icon': Icons.fastfood},
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
      ],
    },
    {
      'name': 'Карта 4',
      'number': '5432',
      'categories': [
        {'name': 'Транспорт', 'percent': 7, 'icon': Icons.directions_bus},
        {'name': 'Одежда', 'percent': 4, 'icon': Icons.shopping_bag},
        {'name': 'Кино', 'percent': 5, 'icon': Icons.movie},
      ],
    },
    {
      'name': 'Карта 5',
      'number': '1111',
      'categories': [
        {'name': 'Кафе', 'percent': 6, 'icon': Icons.local_cafe},
        {'name': 'Фастфуд', 'percent': 5, 'icon': Icons.fastfood},
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
        {'name': 'Транспорт', 'percent': 4, 'icon': Icons.directions_bus},
      ],
    },
    {
      'name': 'Карта 6',
      'number': '2222',
      'categories': [
        {'name': 'Одежда', 'percent': 5, 'icon': Icons.shopping_bag},
        {'name': 'Кино', 'percent': 6, 'icon': Icons.movie},
        {'name': 'Кафе', 'percent': 4, 'icon': Icons.local_cafe},
      ],
    },
    {
      'name': 'Карта 7',
      'number': '3333',
      'categories': [
        {'name': 'Фастфуд', 'percent': 5, 'icon': Icons.fastfood},
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
        {'name': 'Транспорт', 'percent': 6, 'icon': Icons.directions_bus},
        {'name': 'Одежда', 'percent': 4, 'icon': Icons.shopping_bag},
      ],
    },
    {
      'name': 'Карта 8',
      'number': '4444',
      'categories': [
        {'name': 'Кино', 'percent': 5, 'icon': Icons.movie},
        {'name': 'Кафе', 'percent': 7, 'icon': Icons.local_cafe},
        {'name': 'Фастфуд', 'percent': 4, 'icon': Icons.fastfood},
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
      ],
    },
    {
      'name': 'Карта 9',
      'number': '5555',
      'categories': [
        {'name': 'Транспорт', 'percent': 6, 'icon': Icons.directions_bus},
        {'name': 'Одежда', 'percent': 5, 'icon': Icons.shopping_bag},
        {'name': 'Кино', 'percent': 4, 'icon': Icons.movie},
        {'name': 'Кафе', 'percent': 7, 'icon': Icons.local_cafe},
      ],
    },
    {
      'name': 'Карта 10',
      'number': '6666',
      'categories': [
        {'name': 'Фастфуд', 'percent': 5, 'icon': Icons.fastfood},
        {'name': 'Супермаркеты', 'percent': 3, 'icon': Icons.shopping_cart},
        {'name': 'Транспорт', 'percent': 6, 'icon': Icons.directions_bus},
        {'name': 'Одежда', 'percent': 4, 'icon': Icons.shopping_bag},
        {'name': 'Кино', 'percent': 5, 'icon': Icons.movie},
      ],
    },
  ];

  // Получить список карт
  List<Map<String, dynamic>> get cards => _cards;

  // Получить категории для конкретной карты
  List<Map<String, dynamic>> getCategoriesForCard(String cardNumber) {
    final card = _cards.firstWhere((card) => card['number'] == cardNumber);
    return card['categories'];
  }
}