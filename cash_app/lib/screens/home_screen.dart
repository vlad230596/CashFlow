import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import 'cashback_screen.dart';
import 'cards_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('CashFlow'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Кешбек'),
              Tab(text: 'Карты'),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () async {
                await Provider.of<DataProvider>(context, listen: false).fetchCards();
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            CashbackScreen(),
            CardsScreen(),
          ],
        ),
      ),
    );
  }
}