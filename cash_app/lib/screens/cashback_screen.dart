import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import 'widgets/cashback_item.dart';
import '../utils/category_icons.dart'; 

class CashbackScreen extends StatefulWidget {
  const CashbackScreen({super.key});

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
    final dataProvider = Provider.of<DataProvider>(context, listen: true); // Слушаем изменения
    _filteredData = _getData(dataProvider);
    _sortData();
  }

  List<Map<String, dynamic>> _getData(DataProvider dataProvider) {
    return dataProvider.cards.expand<Map<String, dynamic>>((card) {
      return card.categories.map<Map<String, dynamic>>((category) {
        return {
          'category': category.name,
          'percent': category.percent,
          'cardNumber': card.number,
          'icon': CategoryIcons.getCategoryIcon(category.name),
        };
      });
    }).toList();
  }

  void _sortData() {
    _filteredData.sort((a, b) => b['percent'].compareTo(a['percent']));
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      final dataProvider = Provider.of<DataProvider>(context, listen: true); // Слушаем изменения
      final allData = _getData(dataProvider);

      if (query.isEmpty) {
        _filteredData = allData;
      } else {
        _filteredData = allData.where((item) {
          final category = item['category'].toLowerCase();
          final cardNumber = item['cardNumber'].toLowerCase();
          return category.contains(query) || cardNumber.contains(query);
        }).toList();
      }

      _sortData();
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
          child: Consumer<DataProvider>(
            builder: (context, dataProvider, child) {
              _updateFilteredData(); // Обновляем данные при изменении DataProvider
              return ListView.builder(
                itemCount: _filteredData.length,
                itemBuilder: (context, index) {
                  final item = _filteredData[index];
                  return CashbackItem(
                    category: item['category'],
                    percent: item['percent'],
                    cardNumber: item['cardNumber'],
                    icon: CategoryIcons.getCategoryIcon(item['category']),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}