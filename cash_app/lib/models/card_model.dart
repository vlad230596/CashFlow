import 'dart:convert';

class CardModel {
  final int? id;
  final String? paymentSystem;
  final String? cardType;
  final String? lastFourDigits;
  final int? bankId;
  final int? userId;
  final int? maxCashbackCategories;

  CardModel({
    this.id,
    this.paymentSystem,
    this.cardType,
    this.lastFourDigits,
    this.bankId,
    this.userId,
    this.maxCashbackCategories
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as int,
      paymentSystem: json['payment_system'] as String,
      cardType: json['card_type'] as String,
      lastFourDigits: json['last_four_digits'] as String,
      bankId: json['bank_id'] as int,
      userId: json['user_id'] as int,
      maxCashbackCategories: json['max_cashback_categories'] as int
    );
  }

  static Map<String, dynamic> toJson(CardModel model) {
    final jsonMap = {
      if (model.id != null) 'id': model.id,
      if (model.paymentSystem != null) 'payment_system': model.paymentSystem,
      if (model.cardType != null) 'card_type': model.cardType,
      if (model.lastFourDigits != null) 'last_four_digits': model.lastFourDigits,
      if (model.bankId != null) 'bank_id': model.bankId,
      if (model.userId != null) 'user_id': model.userId,
      if (model.maxCashbackCategories != null) 'max_cashback_categories': model.maxCashbackCategories,
    };
    return jsonMap;
  }
}
