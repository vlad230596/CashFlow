import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_model.dart';

  // Data models
  class BankModel {
    final int id;
    final String name;
    final String? description;

    BankModel({required this.id, required this.name, this.description});
  }

  class UserModel {
    final int id;
    final String name;

    UserModel({required this.id, required this.name});
  }

  class CardModel {
    final int id;
    final String paymentSystem;
    final String cardType;
    final String lastFourDigits;
    final int bankId;
    final int userId;

    CardModel({
      required this.id,
      required this.paymentSystem,
      required this.cardType,
      required this.lastFourDigits,
      required this.bankId,
      required this.userId,
    });
  }

class DataProvider with ChangeNotifier {
  List<BankModel> banks = [];
  List<UserModel> users = [];
  List<CardModel> cards = [];
  String? lastUpdated;
  String? serverIp = '192.168.31.142:5000'; // Default server IP

  var _cashbacks = <CashbackModel>[];

  List<CashbackModel> get cashbacks => _cashbacks;

  Future<void> fetchAllData() async {
    try {
      // Fetch banks
      final banksResponse = await http.get(Uri.parse('http://$serverIp/api/banks'));
      banks = (json.decode(banksResponse.body) as List)
          .map((item) => BankModel(id: item['id'], name: item['name'], description: item['description']))
          .toList();

      // Fetch users
      final usersResponse = await http.get(Uri.parse('http://$serverIp/api/users'));
      users = (json.decode(usersResponse.body) as List)
          .map((item) => UserModel(id: item['id'], name: item['name']))
          .toList();

      // Fetch cards
      final cardsResponse = await http.get(Uri.parse('http://$serverIp/api/cards'));
      cards = (json.decode(cardsResponse.body) as List)
          .map((item) => CardModel(
                id: item['id'],
                paymentSystem: item['payment_system'],
                cardType: item['card_type'],
                lastFourDigits: item['last_four_digits'],
                bankId: item['bank_id'],
                userId: item['user_id'],
              ))
          .toList();

      lastUpdated = DateTime.now().toString();
      notifyListeners();
    } catch (e) {
      // Handle errors
      debugPrint('Error fetching data: $e');
    }
  }



  Future<void> fetchCashbacks() async {
    try {
      final response = await http.get(Uri.parse('http://$serverIp/api/active_cashback'));
      print('response status: ${response.statusCode}');
      print('response body: ${response.body}');
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _cashbacks = data.map((json) => CashbackModel.fromJson(json)).toList();
        print('Server returned: $data');
        await _saveCashbacksLocally(data); // Сохраняем данные локально
        notifyListeners();
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print('Error by loading data: $e');
    }
  }

  Future<void> loadLocalCashbacks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cardsJson = prefs.getString('cards');

    if (cardsJson != null) {
      final List<dynamic> data = json.decode(cardsJson);
      _cashbacks = data.map((json) => CashbackModel.fromJson(json)).toList();
      notifyListeners();
    }
  }

  Future<void> _saveCashbacksLocally(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cashbacks', json.encode(data));
  }


Future<void> addBank(String name, String description) async {
  try {
    final response = await http.post(
      Uri.parse('http://$serverIp/api/banks'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'description': description,
      }),
    );

    if (response.statusCode == 201) {
      final newBank = BankModel(
        id: json.decode(response.body)['id'],
        name: name,
        description: description,
      );
      banks.add(newBank);
      notifyListeners();
    } else {
      throw Exception('Failed to add bank');
    }
  } catch (e) {
    debugPrint('Error adding bank: $e');
    rethrow;
  }
}

Future<void> updateBank(int id, String name, String description) async {
  try {
    final response = await http.put(
      Uri.parse('http://$serverIp/api/banks/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'description': description,
      }),
    );

    if (response.statusCode == 200) {
      final index = banks.indexWhere((bank) => bank.id == id);
      if (index != -1) {
        banks[index] = BankModel(
          id: id,
          name: name,
          description: description,
        );
        notifyListeners();
      }
    } else {
      throw Exception('Failed to update bank');
    }
  } catch (e) {
    debugPrint('Error updating bank: $e');
    rethrow;
  }
}

Future<void> deleteBank(int id) async {
  try {
    final response = await http.delete(
      Uri.parse('http://$serverIp/api/banks/$id'),
    );

    if (response.statusCode == 204) {
      banks.removeWhere((bank) => bank.id == id);
      notifyListeners();
    } else {
      throw Exception('Failed to delete bank');
    }
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
  try {
    final response = await http.post(
      Uri.parse('http://$serverIp/api/cards'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'payment_system': paymentSystem,
        'card_type': cardType,
        'last_four_digits': lastFourDigits,
        'bank_id': bankId,
        'user_id': userId,
      }),
    );

    if (response.statusCode == 201) {
      final newCard = CardModel(
        id: json.decode(response.body)['id'],
        paymentSystem: paymentSystem,
        cardType: cardType,
        lastFourDigits: lastFourDigits,
        bankId: bankId,
        userId: userId,
      );
      cards.add(newCard);
      notifyListeners();
    } else {
      throw Exception('Failed to add card');
    }
  } catch (e) {
    debugPrint('Error adding card: $e');
    rethrow;
  }
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


}