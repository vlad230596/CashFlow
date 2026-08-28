class CashbackCategoryModel {
  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isSelected;
  final double cashbackPercent;
  final int cardId;
  final String? description;
  final String categoryType;
  final bool isSelectionLocked;
  final double? maxCashbackAmount;
  final double? minPurchaseAmount;

  CashbackCategoryModel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isSelected,
    required this.cashbackPercent,
    required this.cardId,
    this.description,
    this.categoryType = 'standard',
    this.isSelectionLocked = false,
    this.maxCashbackAmount,
    this.minPurchaseAmount,
  });

  bool get isStackableBonus => categoryType == 'stackable_bonus';

  factory CashbackCategoryModel.fromJson(Map<String, dynamic> json) {
    return CashbackCategoryModel(
      id: json['id'] as int,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isSelected: json['is_selected'] as bool,
      cashbackPercent: (json['cashback_percent'] as num).toDouble(),
      cardId: json['card_id'] as int,
      description: json['description'] as String?,
      categoryType: json['category_type'] as String? ?? 'standard',
      isSelectionLocked: json['is_selection_locked'] as bool? ?? false,
      maxCashbackAmount: (json['max_cashback_amount'] as num?)?.toDouble(),
      minPurchaseAmount: (json['min_purchase_amount'] as num?)?.toDouble(),
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
      'description': model.description,
      'category_type': model.categoryType,
      'is_selection_locked': model.isSelectionLocked,
      'max_cashback_amount': model.maxCashbackAmount,
      'min_purchase_amount': model.minPurchaseAmount,
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
    String? description,
    String? categoryType,
    bool? isSelectionLocked,
    double? maxCashbackAmount,
    double? minPurchaseAmount,
    bool clearMaxCashbackAmount = false,
    bool clearMinPurchaseAmount = false,
  }) {
    return CashbackCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isSelected: isSelected ?? this.isSelected,
      cashbackPercent: cashbackPercent ?? this.cashbackPercent,
      cardId: cardId ?? this.cardId,
      description: description ?? this.description,
      categoryType: categoryType ?? this.categoryType,
      isSelectionLocked: isSelectionLocked ?? this.isSelectionLocked,
      maxCashbackAmount: clearMaxCashbackAmount
          ? null
          : maxCashbackAmount ?? this.maxCashbackAmount,
      minPurchaseAmount: clearMinPurchaseAmount
          ? null
          : minPurchaseAmount ?? this.minPurchaseAmount,
    );
  }
}
