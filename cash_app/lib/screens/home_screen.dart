import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../services/cashback_import_launcher.dart';
import 'cashback_screen.dart';
import 'cards_screen.dart';
import 'monthly_cashback_screen.dart';
import 'settings/banks_settings.dart';
import 'settings/users_settings.dart';
import 'settings/cards_settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Future<void> _pickCashbackDate(
    BuildContext context,
    DataProvider dataProvider,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: dataProvider.cashbackEffectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selectedDate != null) {
      await dataProvider.setCashbackEffectiveDate(selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CashFlow'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Cashback'),
              Tab(text: 'Cards'),
              Tab(text: 'MonthCashback'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Запросить кэшбэк',
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: () async {
                final error = await launchCashbackImport();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error ??
                          'Chrome открыт. Авторизуйтесь в отмеченных банках и скачайте JSON.',
                    ),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings),
              onSelected: (value) async {
                switch (value) {
                  case 'refresh':
                    final isUpdated = await dataProvider.fetchAllData();
                    //await Provider.of<DataProvider>(context, listen: false).fetchCashbacks();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isUpdated
                              ? 'Data refreshed successfully'
                              : 'Could not refresh data. Showing cached data.',
                        ),
                      ),
                    );
                    break;
                  case 'banks':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => BanksSettingsScreen()),
                    );
                    break;
                  case 'cards':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => CardsSettingsScreen()),
                    );
                    break;
                  case 'users':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => UsersSettingsScreen()),
                    );
                    break;
                  case 'cashbackDate':
                    await _pickCashbackDate(context, dataProvider);
                    break;
                  case 'cashbackDateToday':
                    await dataProvider.setCashbackEffectiveDate(null);
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
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
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
                    value: 'cashbackDate',
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 20),
                        const SizedBox(width: 8),
                        const Text('Cashback date'),
                        const Spacer(),
                        Text(
                          _formatDate(dataProvider.cashbackEffectiveDate),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'cashbackDateToday',
                    enabled: !dataProvider.usesCurrentCashbackDate,
                    child: Row(
                      children: [
                        const Icon(Icons.today, size: 20),
                        const SizedBox(width: 8),
                        const Text('Use today'),
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
            MonthlyCashbackScreen(),
          ],
        ),
      ),
    );
  }
}
