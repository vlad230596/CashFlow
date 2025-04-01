import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import 'card_edit_screen.dart';

import '../../models/bank_model.dart';
import '../../models/user_model.dart';

class CardsSettingsScreen extends StatelessWidget {
  const CardsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    // Helper function to get bank name by ID
    String getBankName(int bankId) {
      final bank = dataProvider.banks.firstWhere(
        (b) => b.id == bankId,
        orElse: () => BankModel(id: -1, name: 'Unknown', description: ''),
      );
      return bank.name!;
    }

    // Helper function to get user name by ID
    String getUserName(int userId) {
      final user = dataProvider.users.firstWhere(
        (u) => u.id == userId,
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
        onRefresh: () => dataProvider.fetchAllData(),
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
                  color: card.paymentSystem == 'Visa' 
                      ? Colors.blue 
                      : Colors.amber,
                ),
                title: Text(
                    '${card.paymentSystem} ${card.cardType} •••• ${card.lastFourDigits}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bank: ${getBankName(card.bankId!)}'),
                    Text('User: ${getUserName(card.userId!)}'),
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