import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_model.dart';

class DataProvider with ChangeNotifier {
  List<CardModel> _cards = [];

  List<CardModel> get cards => _cards;

  Future<void> fetchCards() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.31.142:5000/api/cards'));
      print('response status: ${response.statusCode}');
      print('response body: ${response.body}');
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _cards = data.map((json) => CardModel.fromJson(json)).toList();
        print('Server returned: $data');
        await _saveCardsLocally(data); // Сохраняем данные локально
        notifyListeners();
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print('Error by loading data: $e');
    }
  }

  Future<void> loadLocalCards() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cardsJson = prefs.getString('cards');

    if (cardsJson != null) {
      final List<dynamic> data = json.decode(cardsJson);
      _cards = data.map((json) => CardModel.fromJson(json)).toList();
      notifyListeners();
    }
  }

  Future<void> _saveCardsLocally(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cards', json.encode(data));
  }
}