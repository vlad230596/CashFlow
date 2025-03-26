import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import 'bank_edit_screen.dart';

class BanksSettingsScreen extends StatelessWidget {
  const BanksSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Banks (${dataProvider.banks.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BankEditScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => dataProvider.fetchAllData(),
        child: ListView.builder(
          itemCount: dataProvider.banks.length,
          itemBuilder: (context, index) {
            final bank = dataProvider.banks[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text(bank.name),
                subtitle: Text(bank.description ?? ""),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BankEditScreen(existingBank: bank),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}