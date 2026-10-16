import 'dart:convert';

import '../models/bank_model.dart';
import '../models/card_model.dart';
import '../models/canonical_category_model.dart';
import '../models/user_model.dart';

/// Reference collections behind DataProvider's existing public facade.
/// Indexes are rebuilt from the current lists because legacy callers may still
/// mutate a list directly. This avoids silently retaining outdated identities.
class ReferenceDataStore {
  List<BankModel> banks = [];
  List<UserModel> users = [];
  List<CardModel> cards = [];
  List<CanonicalCategoryModel> canonicalCategories = [];

  Map<int, BankModel> get banksById => {
        for (final item in banks)
          if (item.id != null) item.id!: item,
      };
  Map<int, UserModel> get usersById => {
        for (final item in users) item.id: item,
      };
  Map<int, CardModel> get cardsById => {
        for (final item in cards)
          if (item.id != null) item.id!: item,
      };

  Map<String, String> serialize() => {
        'banks': json.encode(banks.map(BankModel.toJson).toList()),
        'users': json.encode(users.map(UserModel.toJson).toList()),
        'cards': json.encode(cards.map(CardModel.toJson).toList()),
        'canonicalCategories': json.encode(
            canonicalCategories.map(CanonicalCategoryModel.toJson).toList()),
      };

  void clear() {
    banks = [];
    users = [];
    cards = [];
    canonicalCategories = [];
  }
}
