import 'package:cashflow/utils/category_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses one icon for aliases of the same category', () {
    expect(
      CategoryInfo.getCategoryIcon('Красота'),
      CategoryInfo.getCategoryIcon('Парфюмерия и косметика'),
    );
    expect(
      CategoryInfo.getCategoryIcon('Образование'),
      CategoryInfo.getCategoryIcon('Книги и канцтовары'),
    );
    expect(
      CategoryInfo.getCategoryIcon('Детские товары'),
      CategoryInfo.getCategoryIcon('Товары для детей'),
    );
  });

  test('recognizes common names from the current category dataset', () {
    final categories = [
      'Супермаркеты(Город)',
      'Яндекс.Лавка',
      'Кафе, бары и рестораны',
      'Аптеки, медицина',
      'Салоны красоты и спа',
      'Oбразование',
      'Спорт и фитнес',
      'Топливо[город]',
      'Яндекс.Такси',
      'Ж/д билеты',
      'Электроника и бытовая техника',
      'Зоотовары',
      'Ювелирные изделия',
    ];

    for (final category in categories) {
      expect(
        CategoryInfo.getCategoryIcon(category),
        isNot(Icons.storefront),
        reason: category,
      );
    }
  });

  test('gives an unknown store a consistent storefront fallback', () {
    expect(
        CategoryInfo.getCategoryIcon('Уникальный магазин'), Icons.storefront);
    expect(
        CategoryInfo.getCategoryColor('Уникальный магазин'), Colors.blueGrey);
  });
}
