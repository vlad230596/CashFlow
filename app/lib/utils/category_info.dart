import 'package:flutter/material.dart';

class CategoryInfo {
  const CategoryInfo({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  static const _all =
      CategoryInfo(icon: Icons.all_inclusive, color: Colors.blueGrey);
  static const _groceries =
      CategoryInfo(icon: Icons.shopping_cart, color: Colors.green);
  static const _food =
      CategoryInfo(icon: Icons.restaurant, color: Colors.deepOrange);
  static const _fashion =
      CategoryInfo(icon: Icons.shopping_bag, color: Colors.pink);
  static const _health =
      CategoryInfo(icon: Icons.local_pharmacy, color: Colors.red);
  static const _beauty =
      CategoryInfo(icon: Icons.spa, color: Colors.pinkAccent);
  static const _children = CategoryInfo(icon: Icons.toys, color: Colors.cyan);
  static const _education =
      CategoryInfo(icon: Icons.school, color: Colors.indigo);
  static const _fuel =
      CategoryInfo(icon: Icons.local_gas_station, color: Colors.orange);
  static const _taxi =
      CategoryInfo(icon: Icons.local_taxi, color: Colors.amber);
  static const _transport =
      CategoryInfo(icon: Icons.directions_bus, color: Colors.indigo);
  static const _car =
      CategoryInfo(icon: Icons.directions_car, color: Colors.blueGrey);
  static const _home = CategoryInfo(icon: Icons.home_work, color: Colors.brown);
  static const _sport =
      CategoryInfo(icon: Icons.fitness_center, color: Colors.purple);
  static const _travel = CategoryInfo(icon: Icons.flight, color: Colors.blue);
  static const _hotel = CategoryInfo(icon: Icons.hotel, color: Colors.blue);
  static const _train = CategoryInfo(icon: Icons.train, color: Colors.indigo);
  static const _entertainment =
      CategoryInfo(icon: Icons.theater_comedy, color: Colors.deepPurple);
  static const _music =
      CategoryInfo(icon: Icons.music_note, color: Colors.deepPurple);
  static const _art = CategoryInfo(icon: Icons.palette, color: Colors.purple);
  static const _electronics =
      CategoryInfo(icon: Icons.devices, color: Colors.blue);
  static const _flowers =
      CategoryInfo(icon: Icons.local_florist, color: Colors.pink);
  static const _pets = CategoryInfo(icon: Icons.pets, color: Colors.brown);
  static const _jewelry = CategoryInfo(icon: Icons.diamond, color: Colors.teal);
  static const _insurance =
      CategoryInfo(icon: Icons.security, color: Colors.blueGrey);
  static const _utilities =
      CategoryInfo(icon: Icons.receipt_long, color: Colors.blueGrey);
  static const _payments =
      CategoryInfo(icon: Icons.contactless, color: Colors.blue);
  static const _delivery =
      CategoryInfo(icon: Icons.local_shipping, color: Colors.blueGrey);
  static const _services =
      CategoryInfo(icon: Icons.cleaning_services, color: Colors.teal);
  static const _premium = CategoryInfo(icon: Icons.star, color: Colors.amber);
  static const _store =
      CategoryInfo(icon: Icons.storefront, color: Colors.blueGrey);

  static final List<_CategoryRule> _rules = [
    _CategoryRule(r'^\s*\d+\s*$',
        const CategoryInfo(icon: Icons.percent, color: Colors.blueGrey)),
    _CategoryRule(r'premium|премиум|свои плюсы', _premium),
    _CategoryRule(r'каско|осаго|страхован', _insurance),
    _CategoryRule(r'жкх|коммуналь', _utilities),
    _CategoryRule(r'alfa pay|втб pay|qr|оплат[аыу].*телефон|улыбк', _payments),
    _CategoryRule(r'химчист|бытов.*услуг', _services),
    _CategoryRule(r'почт|яндекс доставк|^доставка$', _delivery),
    _CategoryRule(r'топлив|азс|заправ|газпромнефт', _fuel),
    _CategoryRule(r'такси|каршер', _taxi),
    _CategoryRule(r'платн.*дорог',
        const CategoryInfo(icon: Icons.route, color: Colors.blueGrey)),
    _CategoryRule(r'автозапчаст|автоуслуг|аренд.*авто|покупк.*авто', _car),
    _CategoryRule(r'транспорт|метро|автобус', _transport),
    _CategoryRule(r'ж\s*д|железнодорож', _train),
    _CategoryRule(r'авиа|путеше|тревел|travel|туту|tripster', _travel),
    _CategoryRule(r'отел|островок', _hotel),
    _CategoryRule(r'аптек|лекарств|медицин|здоров|анализ', _health),
    _CategoryRule(
        r'красот|космет|парфюм|салон|спа|летуал|рив гош|м косметик', _beauty),
    _CategoryRule(r'детск|товар.*дет|игруш|малыш', _children),
    _CategoryRule(
        r'образован|обучен|книг|канцтовар|школ|курс|университет', _education),
    _CategoryRule(r'спорт|фитнес|активн.*отдых|спортмастер', _sport),
    _CategoryRule(r'дом|ремонт|мебел|hoff|строй|товар.*дома', _home),
    _CategoryRule(
        r'одеж|обув|шопинг|fashion|zolla|lamoda|sela|superstep|duty free',
        _fashion),
    _CategoryRule(r'ювелир|ювилир|adamas|аксессуар|часы', _jewelry),
    _CategoryRule(r'животн|питом|зоотовар', _pets),
    _CategoryRule(r'цвет|подар|сувенир', _flowers),
    _CategoryRule(r'музык', _music),
    _CategoryRule(r'искусств|культур|музе|выстав|хобби|творчеств|фото', _art),
    _CategoryRule(r'кино|театр|афиша|развлеч|кинопоиск|start', _entertainment),
    _CategoryRule(r'электрон|техник|м видео|эльдорадо|wollmer|цифров|интернет',
        _electronics),
    _CategoryRule(
        r'кафе|ресторан|фастфуд|бургер кинг|кофе|tasty|еда|деливери|сластен',
        _food),
    _CategoryRule(
        r'супермаркет|продукт|лавк|пятероч|перекрест|магнит|дикси|ашан|вкусвилл|купер|мегамаркет',
        _groceries),
    _CategoryRule(r'все|все покупки|на все|за все', _all),
  ];

  static CategoryInfo getCategoryInfo(String category) {
    final normalized = _normalize(category);
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(normalized)) return rule.info;
    }
    return _store;
  }

  static IconData getCategoryIcon(String category) =>
      getCategoryInfo(category).icon;

  static Color getCategoryColor(String category) =>
      getCategoryInfo(category).color;

  static String _normalize(String value) {
    var normalized = value.toLowerCase().replaceAll('ё', 'е');
    if (RegExp(r'[а-я]').hasMatch(normalized)) {
      normalized = normalized
          .replaceAll('a', 'а')
          .replaceAll('b', 'в')
          .replaceAll('c', 'с')
          .replaceAll('e', 'е')
          .replaceAll('k', 'к')
          .replaceAll('o', 'о');
    }
    return normalized.replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ').trim();
  }
}

class _CategoryRule {
  _CategoryRule(String pattern, this.info)
      : pattern = RegExp(pattern, caseSensitive: false);

  final RegExp pattern;
  final CategoryInfo info;
}
