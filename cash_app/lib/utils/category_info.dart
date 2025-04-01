import 'package:flutter/material.dart';

class CategoryInfo {
  final IconData icon;
  final Color color;

  const CategoryInfo({required this.icon, required this.color});

  // Создаем единый источник данных для категорий
  static final Map<String, CategoryInfo> _categories = {
    // Основные категории
    'Всё': CategoryInfo(icon: Icons.all_inclusive, color: Colors.blueGrey),
    'Аренда авто': CategoryInfo(icon: Icons.directions_car, color: Colors.deepPurple),
    'Дом и ремонт': CategoryInfo(icon: Icons.home_work, color: Colors.brown),
    'Покупка авто': CategoryInfo(icon: Icons.car_repair, color: Colors.deepOrange),
    'Аксессуары': CategoryInfo(icon: Icons.watch, color: Colors.teal),
    'Товары для здоровья': CategoryInfo(icon: Icons.medical_services, color: Colors.redAccent),
    'Перекрёсток': CategoryInfo(icon: Icons.shopping_cart, color: Colors.green),
    'Искусство': CategoryInfo(icon: Icons.palette, color: Colors.pinkAccent),
    'Одежда и обувь': CategoryInfo(icon: Icons.shopping_bag, color: Colors.pink),
    'Развлечения': CategoryInfo(icon: Icons.celebration, color: Colors.purpleAccent),
    'Такси': CategoryInfo(icon: Icons.local_taxi, color: Colors.black),
    'Транспорт': CategoryInfo(icon: Icons.directions_bus, color: Colors.indigo),
    'Электроника и бытовая техника': CategoryInfo(icon: Icons.electrical_services, color: Colors.blue),
    'Цветы': CategoryInfo(icon: Icons.local_florist, color: Colors.red.shade300),
    'Автозапчасти': CategoryInfo(icon: Icons.build, color: Colors.orange),
    'Активный отдых': CategoryInfo(icon: Icons.sports_soccer, color: Colors.greenAccent),
    'Отели в Тревел': CategoryInfo(icon: Icons.hotel, color: Colors.blueAccent),
    'Duty free': CategoryInfo(icon: Icons.luggage, color: Colors.amber),
    'Аптеки': CategoryInfo(icon: Icons.local_pharmacy, color: Colors.red.shade700),
    'Топливо и АЗС': CategoryInfo(icon: Icons.local_gas_station, color: Colors.orangeAccent),
    'Фитнес': CategoryInfo(icon: Icons.fitness_center, color: Colors.purple),
    'Ж/д билеты': CategoryInfo(icon: Icons.train, color: Colors.blue.shade800),
    'М.Видео Онлайн': CategoryInfo(icon: Icons.tv, color: Colors.red),
    'Т-Страхование': CategoryInfo(icon: Icons.security, color: Colors.blueGrey),
    'Шопинг[город]': CategoryInfo(icon: Icons.shopping_cart, color: Colors.deepPurpleAccent),
    'Топливо[город]': CategoryInfo(icon: Icons.ev_station, color: Colors.orange),
    'Спорттовары': CategoryInfo(icon: Icons.sports_baseball, color: Colors.green),
    // Добавьте другие категории по аналогии
  };

  // Метод для получения информации о категории
  static CategoryInfo getCategoryInfo(String category) {
    return _categories[category] ?? 
           CategoryInfo(icon: Icons.category, color: Colors.grey);
  }

  // Методы для обратной совместимости
  static IconData getCategoryIcon(String category) {
    return getCategoryInfo(category).icon;
  }

  static Color getCategoryColor(String category) {
    return getCategoryInfo(category).color;
  }
}