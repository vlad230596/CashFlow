class CardModel {
  final String name;
  final String number;
  final List<CategoryModel> categories;

  CardModel({
    required this.name,
    required this.number,
    required this.categories,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      name: json['name'],
      number: json['number'],
      categories: (json['categories'] as List)
          .map((category) => CategoryModel.fromJson(category))
          .toList(),
    );
  }
}

class CategoryModel {
  final String name;
  final double percent;

  CategoryModel({
    required this.name,
    required this.percent
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      name: json['name'],
      percent: json['percent']
    );
  }
}