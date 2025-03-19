import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data_provider.dart';
import 'widgets/cashback_item.dart';

class CashbackScreen extends StatefulWidget {
  @override
  _CashbackScreenState createState() => _CashbackScreenState();
}

class _CashbackScreenState extends State<CashbackScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredData = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateFilteredData(); // Обновляем данные при изменении зависимостей
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilteredData() {
    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    _filteredData = dataProvider.cards.expand<Map<String, dynamic>>((card) {
      return card['categories'].map<Map<String, dynamic>>((category) {
        return {
          'category': category['name'],
          'percent': category['percent'],
          'cardNumber': card['number'],
          'icon': category['icon'],
        };
      });
    }).toList();

    // Сортировка по убыванию процента кешбека
    _filteredData.sort((a, b) => b['percent'].compareTo(a['percent']));
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      final dataProvider = Provider.of<DataProvider>(context, listen: false);
      final allData = dataProvider.cards.expand<Map<String, dynamic>>((card) {
        return card['categories'].map<Map<String, dynamic>>((category) {
          return {
            'category': category['name'],
            'percent': category['percent'],
            'cardNumber': card['number'],
            'icon': category['icon'],
          };
        });
      }).toList();

      if (query.isEmpty) {
        // Если запрос пуст, показываем все данные
        _filteredData = allData;
      } else {
        // Фильтруем данные по запросу
        _filteredData = allData.where((item) {
          final category = item['category'].toLowerCase();
          final cardNumber = item['cardNumber'].toLowerCase();
          return category.contains(query) || cardNumber.contains(query);
        }).toList();
      }

      // Сортировка по убыванию процента кешбека
      _filteredData.sort((a, b) => b['percent'].compareTo(a['percent']));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredData.length,
            itemBuilder: (context, index) {
              final item = _filteredData[index];
              return CashbackItem(
                category: item['category'],
                percent: item['percent'],
                cardNumber: item['cardNumber'],
                icon: item['icon'],
              );
            },
          ),
        ),
      ],
    );
  }
}