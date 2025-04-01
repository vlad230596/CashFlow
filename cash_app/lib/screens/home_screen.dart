import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import 'cashback_screen.dart';
import 'cards_screen.dart';
import 'monthly_cashback_screen.dart';
import 'settings/banks_settings.dart';
import 'settings/users_settings.dart';
import 'settings/cards_settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CashFlow'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Cashback'),
              Tab(text: 'Cards'),
              // Tab(text: 'MonthCashback'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings),
              onSelected: (value) async {
                switch (value) {
                  case 'refresh':
                    await dataProvider.fetchAllData();
                    //await Provider.of<DataProvider>(context, listen: false).fetchCashbacks();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data refreshed successfully')),
                    );
                    break;
                  case 'banks':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => BanksSettingsScreen()),
                    );
                    break;
                  case 'cards':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CardsSettingsScreen()),
                    );
                    break;
                  case 'users':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => UsersSettingsScreen()),
                    );
                    break;
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        const Icon(Icons.refresh, size: 20),
                        const SizedBox(width: 8),
                        const Text('Refresh'),
                        const Spacer(),
                        Text(
                          dataProvider.lastUpdated ?? 'Never',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'banks',
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance, size: 20),
                        const SizedBox(width: 8),
                        const Text('Banks'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${dataProvider.banks.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Updated Cards item with count
                  PopupMenuItem(
                    value: 'cards',
                    child: Row(
                      children: [
                        const Icon(Icons.credit_card, size: 20),
                        const SizedBox(width: 8),
                        const Text('Cards'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${dataProvider.cards.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Updated Users item with count
                  PopupMenuItem(
                    value: 'users',
                    child: Row(
                      children: [
                        const Icon(Icons.people, size: 20),
                        const SizedBox(width: 8),
                        const Text('Users'),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${dataProvider.users.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'Server: ${dataProvider.serverIp ?? 'not set'}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            CashbackScreen(),
            CardsScreen(),
            // MonthlyCashbackScreen()
          ],
        ),
      ),
    );
  }
}