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
      final jsonMap = {
        if (model.id != null) 'id': model.id,
        if (model.name != null) 'name': model.name,
        if (model.startDate != null) 'start_date': model.startDate.toIso8601String(),
        if (model.endDate != null) 'end_date': model.endDate.toIso8601String(),
        if (model.isSelected != null) 'is_selected': model.isSelected,
        if (model.cashbackPercent != null) 'cashback_percent': model.cashbackPercent,
        if (model.cardId != null) 'card_id': model.cardId,
      };
      return jsonMap;
  }

    CashbackCategoryModel copyWith({
      bool? isSelected,
      double? cashbackPercent,
    }) {
      return CashbackCategoryModel(
        id: id,
        name: name,
        startDate: startDate,
        endDate: endDate,
        isSelected: isSelected ?? this.isSelected,
        cashbackPercent: cashbackPercent ?? this.cashbackPercent,
        cardId: cardId,
      );
    }
  }