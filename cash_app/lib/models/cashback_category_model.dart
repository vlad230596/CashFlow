class CashbackCategoryModel {
  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isSelected;
  final double cashbackPercent;
  final int cardId;

  CashbackCategoryModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isSelected,
    required this.cashbackPercent,
    required this.cardId,
  });

  factory CashbackCategoryModel.fromJson(Map<String, dynamic> json) {
    return CashbackCategoryModel(
      id: json['id'] as int,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isSelected: json['is_selected'] as bool,
      cashbackPercent: (json['cashback_percent'] as num).toDouble(),
      cardId: json['card_id'] as int,
    );
  }

  static Map<String, dynamic> toJson(CashbackCategoryModel model) {
    return {
      'id': model.id,
      'name': model.name,
      'start_date': model.startDate.toIso8601String(),
      'end_date': model.endDate.toIso8601String(),
      'is_selected': model.isSelected,
      'cashback_percent': model.cashbackPercent,
      'card_id': model.cardId,
    };
  }

  CashbackCategoryModel copyWith({
    int? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    bool? isSelected,
    double? cashbackPercent,
    int? cardId,
  }) {
    return CashbackCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isSelected: isSelected ?? this.isSelected,
      cashbackPercent: cashbackPercent ?? this.cashbackPercent,
      cardId: cardId ?? this.cardId,
    );
  }
}
