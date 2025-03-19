import 'package:flutter/material.dart';
import 'cashback_screen.dart';
import 'cards_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Кешбек и карты'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Кешбек'),
              Tab(text: 'Карты'),
            ],
          ),
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