/// A unified cashback category shared by all banks (see backend
/// `canonical_categories.json`). Bank offers keep their own names and are
/// linked to one or more canonical categories.
class CanonicalCategoryModel {
  const CanonicalCategoryModel({
    required this.key,
    required this.title,
    required this.groupKey,
    required this.groupTitle,
    required this.aliases,
    required this.defaultPriority,
  });

  final String key;
  final String title;
  final String groupKey;
  final String groupTitle;

  /// Search synonyms such as «дети» or «заправки».
  final List<String> aliases;

  /// Lower is more important: up to 50 are required needs, up to 80 frequent.
  final int defaultPriority;

  factory CanonicalCategoryModel.fromJson(Map<String, dynamic> json) =>
      CanonicalCategoryModel(
        key: json['key'] as String,
        title: json['title'] as String,
        groupKey: json['group_key'] as String,
        groupTitle: json['group_title'] as String,
        aliases: List<String>.from(json['aliases'] as List? ?? const []),
        defaultPriority: json['default_priority'] as int,
      );

  static Map<String, dynamic> toJson(CanonicalCategoryModel model) => {
        'key': model.key,
        'title': model.title,
        'group_key': model.groupKey,
        'group_title': model.groupTitle,
        'aliases': model.aliases,
        'default_priority': model.defaultPriority,
      };
}
