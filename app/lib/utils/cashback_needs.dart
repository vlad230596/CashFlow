import '../models/canonical_category_model.dart';
import '../models/cashback_category_model.dart';

/// Name-based grouping for offers the server has not linked to a canonical
/// category (brand offers, «Все покупки», data cached before the catalogue).
///
/// The UI keeps the original bank title visible and explicitly describes this
/// match as approximate.
String normalizedCashbackCategoryName(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();

  bool containsAny(Iterable<String> words) =>
      words.any((word) => normalized.contains(word));

  if (containsAny(['аптек', 'лекарств'])) return 'Аптеки';
  if (containsAny(['супермаркет', 'продукт', 'groceries'])) {
    return 'Продукты и супермаркеты';
  }
  if (containsAny(['кафе', 'ресторан', 'фастфуд'])) {
    return 'Кафе и рестораны';
  }
  if (containsAny(['одежд', 'обув', 'fashion'])) return 'Одежда и обувь';
  if (containsAny(['детск', 'для детей', 'игруш', 'малыш'])) {
    return 'Детские товары';
  }
  if (containsAny(['азс', 'топлив', 'заправ'])) return 'АЗС и топливо';
  if (containsAny(['красот', 'космет', 'парфюм', 'бьюти', 'салон', 'спа'])) {
    return 'Красота и уход';
  }
  if (containsAny(['такси', 'каршер'])) return 'Такси и каршеринг';
  if (containsAny(['транспорт', 'метро', 'автобус'])) {
    return 'Общественный транспорт';
  }
  if (containsAny(['дом и ремонт', 'стройматериал', 'товары для дома'])) {
    return 'Дом и ремонт';
  }
  if (containsAny(['спорт', 'фитнес', 'активный отдых'])) {
    return 'Спорт и активный отдых';
  }
  if (containsAny([
    'образован',
    'обучен',
    'курс',
    'школ',
    'университет',
    'репетитор',
    'книг',
  ])) {
    return 'Образование';
  }
  if (containsAny(['кино', 'развлеч'])) return 'Развлечения';
  if (containsAny(['путешеств', 'авиабилет', 'отел', 'travel'])) {
    return 'Путешествия';
  }
  if (containsAny(['все покупки', 'на все', 'everything'])) {
    return 'Все покупки';
  }
  if (containsAny(['онлайн покуп', 'online'])) return 'Онлайн-покупки';

  if (normalized.isEmpty) return value.trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

/// Lower values are shown first. Unknown names are treated as niche offers,
/// including cashback tied to a particular shop or brand.
int cashbackCategorySortPriority(String categoryName) {
  switch (normalizedCashbackCategoryName(categoryName)) {
    case 'Продукты и супермаркеты':
      return 10;
    case 'Кафе и рестораны':
      return 20;
    case 'Одежда и обувь':
      return 30;
    case 'Детские товары':
      return 35;
    case 'Аптеки':
      return 40;
    case 'Все покупки':
      return 45;
    case 'АЗС и топливо':
      return 50;
    case 'Красота и уход':
      return 55;
    case 'Общественный транспорт':
      return 60;
    case 'Такси и каршеринг':
      return 65;
    case 'Дом и ремонт':
      return 70;
    case 'Образование':
      return 75;
    case 'Спорт и активный отдых':
      return 80;
    case 'Путешествия':
      return 90;
    case 'Онлайн-покупки':
      return 100;
    case 'Развлечения':
      return 110;
    default:
      return 1000;
  }
}

/// Groups plan offers by unified (canonical) categories.
///
/// An offer covers every canonical category the server linked it to, so a
/// bank's «Кафе и рестораны» that includes fast food appears under both
/// needs. Offers without links (brand offers, «Все покупки», data cached
/// before the catalogue existed) keep the name-based grouping.
class CashbackNeedCatalog {
  CashbackNeedCatalog(List<CanonicalCategoryModel> categories)
      : _byKey = {for (final item in categories) item.key: item},
        _byTitle = {for (final item in categories) item.title: item};

  final Map<String, CanonicalCategoryModel> _byKey;
  final Map<String, CanonicalCategoryModel> _byTitle;

  List<String> titlesFor(CashbackCategoryModel offer) {
    final titles = [
      for (final key in offer.canonicalKeys)
        if (_byKey[key] case final category?) category.title,
    ];
    return titles.isNotEmpty
        ? titles
        : [normalizedCashbackCategoryName(offer.name)];
  }

  String primaryTitle(CashbackCategoryModel offer) => titlesFor(offer).first;

  int priority(String title) =>
      _byTitle[title]?.defaultPriority ?? cashbackCategorySortPriority(title);

  List<String> aliases(String title) => _byTitle[title]?.aliases ?? const [];

  /// How a search query relates to a need: by its title or by a synonym.
  NeedMatch match(String title, String query) {
    final normalized = normalizeNeedQuery(query);
    if (normalized.isEmpty) return NeedMatch.none;
    if (normalizeNeedQuery(title).contains(normalized)) return NeedMatch.title;
    if (aliases(title)
        .any((alias) => normalizeNeedQuery(alias).contains(normalized))) {
      return NeedMatch.alias;
    }
    // The fallback name rules know common synonyms («лекарства» → «Аптеки»).
    if (normalizedCashbackCategoryName(query) == title) return NeedMatch.alias;
    return NeedMatch.none;
  }
}

enum NeedMatch { none, title, alias }

String normalizeNeedQuery(String value) =>
    value.toLowerCase().replaceAll('ё', 'е').trim();
