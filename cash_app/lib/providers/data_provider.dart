import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import '../models/bank_model.dart';
import '../models/user_model.dart';
import '../models/cashback_category_model.dart';

class DataProvider with ChangeNotifier {
  List<BankModel> banks = [];
  List<UserModel> users = [];
  List<CardModel> cards = [];
  List<CashbackCategoryModel> cashbackCategories = [];
  List<CashbackCategoryModel> activeCashbackCategories = [];
  String? lastUpdated;
  String? serverIp = '192.168.31.142:5000'; // Default server IP
  DateTime? _cashbackDateOverride;

  DateTime get cashbackEffectiveDate =>
      _dateOnly(_cashbackDateOverride ?? DateTime.now());

  bool get usesCurrentCashbackDate => _cashbackDateOverride == null;

  List<CashbackCategoryModel> get effectiveActiveCashbackCategories {
    final source = cashbackCategories.isNotEmpty
        ? cashbackCategories
        : activeCashbackCategories;

    return source.where((category) {
      final effectiveDate = cashbackEffectiveDate;
      final startDate = _dateOnly(category.startDate);
      final endDate = _dateOnly(category.endDate);

      return category.isSelected &&
          !effectiveDate.isBefore(startDate) &&
          effectiveDate.isBefore(endDate);
    }).toList();
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> setCashbackEffectiveDate(DateTime? date) async {
    _cashbackDateOverride = date == null ? null : _dateOnly(date);

    final prefs = await SharedPreferences.getInstance();
    if (_cashbackDateOverride == null) {
      await prefs.remove('cashbackEffectiveDate');
    } else {
      await prefs.setString(
        'cashbackEffectiveDate',
        _cashbackDateOverride!.toIso8601String(),
      );
    }

    notifyListeners();
  }

  Future<List<T>> receiveFromServer<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response =
        await http.get(Uri.parse('http://$serverIp/api/$endpoint'));

    if (response.statusCode != 200) {
      throw Exception('Failed to load $endpoint: ${response.statusCode}');
    }

    final result = (json.decode(response.body) as List)
        .map((item) => fromJson(item))
        .toList();
    return result;
  }

  Future<void> initialize() async {
    await loadLocalData();
    unawaited(fetchAllData());
  }

  Future<T> addItemToServer<T>(
      String endpoint,
      T item,
      T Function(Map<String, dynamic>) fromJson,
      Map<String, dynamic> Function(T) toJson) async {
    try {
      final response = await http.post(
        Uri.parse('http://$serverIp/api/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(toJson(item)),
      );

      if (response.statusCode == 201) {
        final newItem = fromJson(json.decode(response.body));
        return newItem;
      } else {
        throw Exception('Failed to add item');
      }
    } catch (e) {
      debugPrint('Error adding item: $e');
      rethrow;
    }
  }

  Future<void> deleteItemFromServer(String endpoint, int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://$serverIp/api/$endpoint/$id'),
      );

      if (response.statusCode == 204) {
        debugPrint('Delete from server item with id $id from $endpoint');
      } else {
        throw Exception('Failed to delete bank');
      }
    } catch (e) {
      debugPrint('Error deleting bank: $e');
      rethrow;
    }
  }

  Future<T> updateItemOnServer<T>(
      String endpoint,
      int id,
      T item,
      T Function(Map<String, dynamic>) fromJson,
      Map<String, dynamic> Function(T) toJson) async {
    try {
      final response = await http.put(
        Uri.parse('http://$serverIp/api/$endpoint/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(toJson(item)),
      );

      if (response.statusCode == 200) {
        return fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update bank');
      }
    } catch (e) {
      debugPrint('Error updating bank: $e');
      rethrow;
    }
  }

  Future<bool> fetchAllData() async {
    try {
      final fetchedBanks = await receiveFromServer("banks", BankModel.fromJson);
      final fetchedUsers = await receiveFromServer("users", UserModel.fromJson);
      final fetchedCards = await receiveFromServer("cards", CardModel.fromJson);
      final fetchedActiveCashbackCategories = await receiveFromServer(
        "active_cashback",
        CashbackCategoryModel.fromJson,
      );
      final fetchedCashbackCategories = await receiveFromServer(
        "cashback",
        CashbackCategoryModel.fromJson,
      );

      banks = fetchedBanks;
      users = fetchedUsers;
      cards = fetchedCards;
      activeCashbackCategories = fetchedActiveCashbackCategories;
      cashbackCategories = fetchedCashbackCategories;
      lastUpdated = DateTime.now().toString();
      await _saveDataLocally();
      notifyListeners();
      return true;
    } catch (e) {
      // Handle errors
      debugPrint('Error fetching data: $e');
      return false;
    }
  }

  Future<void> fetchCashbackCategories() async {
    try {
      final response = await http.get(
        Uri.parse('http://$serverIp/api/cashback'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        cashbackCategories =
            data.map((json) => CashbackCategoryModel.fromJson(json)).toList();
        notifyListeners();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching cashback categories: $e');
      rethrow;
    }
  }

  // Future<void> fetchCashbacks() async {
  //   try {
  //     final response = await http.get(Uri.parse('http://$serverIp/api/active_cashback'));
  //     print('response status: ${response.statusCode}');
  //     print('response body: ${response.body}');
  //     if (response.statusCode == 200) {
  //       final List<dynamic> data = json.decode(response.body);
  //       _cashbacks = data.map((json) => CashbackModel.fromJson(json)).toList();
  //       print('Server returned: $data');
  //       await _saveCashbacksLocally(data); // Сохраняем данные локально
  //       notifyListeners();
  //     } else {
  //       throw Exception('Failed to load data');
  //     }
  //   } catch (e) {
  //     print('Error by loading data: $e');
  //   }
  // }

  Future<void> loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cachedBanks = prefs.getString('banks');
      final cachedUsers = prefs.getString('users');
      final cachedCards = prefs.getString('cards');
      final cachedCashbackCategories = prefs.getString('cashbackCategories');
      final cachedActiveCashbackCategories =
          prefs.getString('activeCashbackCategories');
      final cachedCashbackEffectiveDate =
          prefs.getString('cashbackEffectiveDate');

      if (cachedCashbackEffectiveDate != null) {
        _cashbackDateOverride =
            _dateOnly(DateTime.parse(cachedCashbackEffectiveDate));
      }

      if (cachedBanks != null) {
        banks = (json.decode(cachedBanks) as List)
            .map((item) => BankModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedUsers != null) {
        users = (json.decode(cachedUsers) as List)
            .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedCards != null) {
        cards = (json.decode(cachedCards) as List)
            .map((item) => CardModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedCashbackCategories != null) {
        cashbackCategories = (json.decode(cachedCashbackCategories) as List)
            .map((item) =>
                CashbackCategoryModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (cachedActiveCashbackCategories != null) {
        activeCashbackCategories = (json.decode(cachedActiveCashbackCategories)
                as List)
            .map((item) =>
                CashbackCategoryModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loadLocalData: $e');
    }
  }

  Future<void> _saveDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('banks',
        json.encode(banks.map((bank) => BankModel.toJson(bank)).toList()));
    prefs.setString('users',
        json.encode(users.map((user) => UserModel.toJson(user)).toList()));
    prefs.setString('cards',
        json.encode(cards.map((card) => CardModel.toJson(card)).toList()));
    prefs.setString(
        'cashbackCategories',
        json.encode(cashbackCategories
            .map((cashbackCategory) =>
                CashbackCategoryModel.toJson(cashbackCategory))
            .toList()));
    prefs.setString(
        'activeCashbackCategories',
        json.encode(activeCashbackCategories
            .map((cashbackCategory) =>
                CashbackCategoryModel.toJson(cashbackCategory))
            .toList()));
  }

  Future<void> addBank(String name, String description) async {
    final item = BankModel(name: name, description: description);
    final result = await addItemToServer(
        "banks", item, BankModel.fromJson, BankModel.toJson);
    banks.add(result);
    notifyListeners();
  }

  Future<void> updateBank(int id, String name, String description) async {
    try {
      final updated = await updateItemOnServer(
          'banks',
          id,
          BankModel(name: name, description: description),
          BankModel.fromJson,
          BankModel.toJson);
      banks[banks.indexWhere((bank) => bank.id == id)] = updated;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating bank: $e');
      rethrow;
    }
  }

  Future<void> deleteBank(int id) async {
    try {
      await deleteItemFromServer('banks', id);
      banks.removeWhere((bank) => bank.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting bank: $e');
      rethrow;
    }
  }

  Future<void> addUser(String name) async {
    try {
      final response = await http.post(
        Uri.parse('http://$serverIp/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
        }),
      );

      if (response.statusCode == 201) {
        final newUser = UserModel(
          id: json.decode(response.body)['id'],
          name: name,
        );
        users.add(newUser);
        notifyListeners();
      } else {
        throw Exception('Failed to add user');
      }
    } catch (e) {
      debugPrint('Error adding user: $e');
      rethrow;
    }
  }

  Future<void> updateUser(int id, String name) async {
    try {
      final response = await http.put(
        Uri.parse('http://$serverIp/api/users/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
        }),
      );

      if (response.statusCode == 200) {
        final index = users.indexWhere((user) => user.id == id);
        if (index != -1) {
          users[index] = UserModel(
            id: id,
            name: name,
          );
          notifyListeners();
        }
      } else {
        throw Exception('Failed to update user');
      }
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  Future<void> deleteUser(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://$serverIp/api/users/$id'),
      );

      if (response.statusCode == 204) {
        users.removeWhere((user) => user.id == id);
        notifyListeners();
      } else {
        throw Exception('Failed to delete user');
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow;
    }
  }

  Future<void> addCard(
    String paymentSystem,
    String cardType,
    String lastFourDigits,
    int bankId,
    int userId,
  ) async {
    final item = CardModel(
        paymentSystem: paymentSystem,
        cardType: cardType,
        lastFourDigits: lastFourDigits,
        bankId: bankId,
        userId: userId);
    final result = await addItemToServer(
        "cards", item, CardModel.fromJson, CardModel.toJson);
    cards.add(result);
    notifyListeners();
  }

  CardModel getCardById(int cardId) {
    return cards.firstWhere(
      (card) => card.id == cardId,
      orElse: () => CardModel(
        id: cardId,
        paymentSystem: '',
        cardType: '',
        lastFourDigits: '????',
      ),
    );
  }

  String getCardName(int cardId) {
    final card = getCardById(cardId);
    final userName = users
        .where((user) => user.id == card.userId)
        .map((user) => user.name)
        .firstOrNull;
    final bankName = banks
        .where((bank) => bank.id == card.bankId)
        .map((bank) => bank.name)
        .firstOrNull;

    if (userName == null && bankName == null) {
      return 'Unknown card';
    }

    return [
      if (userName != null) userName,
      if (bankName != null) bankName,
    ].join(' ');
  }

  Future<void> updateCard(
    int id,
    String paymentSystem,
    String cardType,
    String lastFourDigits,
    int bankId,
    int userId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('http://$serverIp/api/cards/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'payment_system': paymentSystem,
          'card_type': cardType,
          'last_four_digits': lastFourDigits,
          'bank_id': bankId,
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        final index = cards.indexWhere((card) => card.id == id);
        if (index != -1) {
          cards[index] = CardModel(
            id: id,
            paymentSystem: paymentSystem,
            cardType: cardType,
            lastFourDigits: lastFourDigits,
            bankId: bankId,
            userId: userId,
          );
          notifyListeners();
        }
      } else {
        throw Exception('Failed to update card');
      }
    } catch (e) {
      debugPrint('Error updating card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://$serverIp/api/cards/$id'),
      );

      if (response.statusCode == 204) {
        cards.removeWhere((card) => card.id == id);
        notifyListeners();
      } else {
        throw Exception('Failed to delete card');
      }
    } catch (e) {
      debugPrint('Error deleting card: $e');
      rethrow;
    }
  }

  Future<void> addCashbackCategory(
    String name,
    double cashbackPercent,
    int cardId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return addCashbackCategoryQuietly(
      name,
      cashbackPercent,
      cardId,
      startDate,
      endDate,
      notify: true,
    );
  }

  Future<void> addCashbackCategoryQuietly(
    String name,
    double cashbackPercent,
    int cardId,
    DateTime startDate,
    DateTime endDate, {
    required bool notify,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('http://$serverIp/api/cashback'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'cashback_percent': cashbackPercent,
          'card_id': cardId,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'is_selected': false,
        }),
      );

      if (response.statusCode == 201) {
        final newCategory =
            CashbackCategoryModel.fromJson(json.decode(response.body));
        cashbackCategories.add(newCategory);
        if (notify) {
          notifyListeners();
        }
      } else {
        throw Exception('Failed to add category: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error adding cashback category: $e');
      rethrow;
    }
  }

  void notifyCashbackCategoriesChanged() {
    notifyListeners();
  }

  Future<void> updateCashbackCategory(
    CashbackCategoryModel category,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('http://$serverIp/api/cashback/${category.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(CashbackCategoryModel.toJson(category)),
      );

      if (response.statusCode == 200) {
        final updatedCategory =
            CashbackCategoryModel.fromJson(json.decode(response.body));
        final index =
            cashbackCategories.indexWhere((c) => c.id == updatedCategory.id);
        if (index != -1) {
          cashbackCategories[index] = updatedCategory;
        } else {
          cashbackCategories.add(updatedCategory);
        }

        final activeIndex = activeCashbackCategories
            .indexWhere((c) => c.id == updatedCategory.id);
        if (activeIndex != -1) {
          if (updatedCategory.isSelected) {
            activeCashbackCategories[activeIndex] = updatedCategory;
          } else {
            activeCashbackCategories.removeAt(activeIndex);
          }
        } else if (updatedCategory.isSelected) {
          activeCashbackCategories.add(updatedCategory);
        }

        await _saveDataLocally();
        notifyListeners();
      } else {
        throw Exception('Failed to update category: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating cashback category: $e');
      rethrow;
    }
  }

  Future<void> toggleCategorySelection(int categoryId, bool isSelected) async {
    try {
      final response = await http.put(
        Uri.parse('http://$serverIp/api/cashback/$categoryId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'is_selected': isSelected}),
      );

      if (response.statusCode == 200) {
        final index = cashbackCategories.indexWhere((c) => c.id == categoryId);
        if (index != -1) {
          cashbackCategories[index] =
              cashbackCategories[index].copyWith(isSelected: isSelected);
          notifyListeners();
        }
      } else {
        throw Exception('Failed to update category: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error toggling category selection: $e');
      rethrow;
    }
  }
}
