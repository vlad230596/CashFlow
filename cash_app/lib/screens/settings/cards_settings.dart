import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bank_model.dart';
import '../../models/user_model.dart';
import '../../providers/data_provider.dart';
import 'card_edit_screen.dart';

class CardsSettingsScreen extends StatelessWidget {
  const CardsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    String getBankName(int? bankId) {
      final bank = dataProvider.banks.firstWhere(
        (bank) => bank.id == bankId,
        orElse: () => BankModel(id: -1, name: 'Unknown', description: ''),
      );
      return bank.name ?? 'Unknown';
    }

    String getUserName(int? userId) {
      final user = dataProvider.users.firstWhere(
        (user) => user.id == userId,
        orElse: () => UserModel(id: -1, name: 'Unknown'),
      );
      return user.name;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Cards (${dataProvider.cards.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CardEditScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await dataProvider.fetchAllData();
        },
        child: ListView.builder(
          itemCount: dataProvider.cards.length,
          itemBuilder: (context, index) {
            final card = dataProvider.cards[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: Icon(
                  card.paymentSystem == 'Visa'
                      ? Icons.credit_card
                      : Icons.payment,
                  color:
                      card.paymentSystem == 'Visa' ? Colors.blue : Colors.amber,
                ),
                title: Text(
                  '${card.paymentSystem ?? 'Unknown'} ${card.cardType ?? ''} '
                  '•••• ${card.lastFourDigits ?? '????'}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bank: ${getBankName(card.bankId)}'),
                    Text('User: ${getUserName(card.userId)}'),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CardEditScreen(existingCard: card),
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
