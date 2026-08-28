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

  Future<int?> _selectImportUser(
    BuildContext context,
    DataProvider dataProvider,
  ) async {
    if (dataProvider.users.isEmpty) return null;
    if (dataProvider.users.length == 1) return dataProvider.users.single.id;

    var selectedUserId = dataProvider.users.first.id;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Кому импортировать категории?'),
        content: StatefulBuilder(
          builder: (context, setState) => DropdownButtonFormField<int>(
            initialValue: selectedUserId,
            decoration: const InputDecoration(
              labelText: 'Владелец карт',
              border: OutlineInputBorder(),
            ),
            items: dataProvider.users
                .map(
                  (user) => DropdownMenuItem<int>(
                    value: user.id,
                    child: Text(user.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => selectedUserId = value);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, selectedUserId),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  Future<void> _importCashback(
    BuildContext context,
    DataProvider dataProvider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await pickCashbackImportFile();
      if (file == null || !context.mounted) return;
      final userId = await _selectImportUser(context, dataProvider);
      if (userId == null || !context.mounted) return;

      final result = await dataProvider.importCashbackDocument(
        file.contents,
        userId,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Импортировано банков: ${result.importedBanks}; '
            'создано: ${result.created}, обновлено: ${result.updated}'
            '${result.skippedBanks == 0 ? '' : ', пропущено банков: ${result.skippedBanks}'}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось импортировать JSON: $error')),
      );
    }
  }

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
              tooltip: 'Импортировать кэшбэк из JSON',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: dataProvider.canEdit
                  ? () => _importCashback(context, dataProvider)
                  : null,
            ),
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
                  case 'logout':
                    await dataProvider.logout();
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
                  if (dataProvider.isAdmin) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'banks',
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance, size: 20),
                          const SizedBox(width: 8),
                          const Text('Banks'),
                          const Spacer(),
                          Text('${dataProvider.banks.length}'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cards',
                      child: Row(
                        children: [
                          const Icon(Icons.credit_card, size: 20),
                          const SizedBox(width: 8),
                          const Text('Cards'),
                          const Spacer(),
                          Text('${dataProvider.cards.length}'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'users',
                      child: Row(
                        children: [
                          const Icon(Icons.people, size: 20),
                          const SizedBox(width: 8),
                          const Text('Users'),
                          const Spacer(),
                          Text('${dataProvider.users.length}'),
                        ],
                      ),
                    ),
                  ],
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
                      '${dataProvider.currentAuthUser?.username} · '
                      '${dataProvider.currentAuthUser?.role}\n'
                      'Server: ${dataProvider.serverIp}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 20),
                        SizedBox(width: 8),
                        Text('Выйти'),
                      ],
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
