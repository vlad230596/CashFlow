import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/data_provider.dart';
import 'widgets/benefit_states_view.dart';

class CashbackScreen extends StatelessWidget {
  const CashbackScreen({
    super.key,
    this.onShellDestinationSelected,
    this.onInternalDetailChanged,
  });

  final ValueChanged<int>? onShellDestinationSelected;
  final ValueChanged<bool>? onInternalDetailChanged;

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final items = provider.effectiveActiveCashbackCategories
              .map(
                (category) => BenefitItemData(
                  category: category,
                  cardLabel: _cardLabel(provider, category.cardId),
                  bankName: _bankName(provider, category.cardId),
                  bankIconKey: _bankIconKey(provider, category.cardId),
                  userName: _userName(provider, category.cardId),
                  userIconKey: _userIconKey(provider, category.cardId),
                  lastFourDigits:
                      provider.getCardById(category.cardId).lastFourDigits,
                ),
              )
              .toList();
          return BenefitStatesView(
            phase: provider.primaryDataPhase,
            hasUsableSnapshot: provider.hasUsableDataSnapshot,
            snapshotUpdatedAt: provider.dataSnapshotUpdatedAt,
            items: items,
            onRefresh: () async {
              await provider.fetchAllData();
            },
            onShellDestinationSelected: onShellDestinationSelected,
            onInternalDetailChanged: onInternalDetailChanged,
          );
        },
      );
}

String? _bankName(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return provider.banks
      .where((bank) => bank.id == card.bankId)
      .map((bank) => bank.name)
      .firstOrNull;
}

String? _bankIconKey(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return provider.banks
      .where((bank) => bank.id == card.bankId)
      .map((bank) => bank.iconKey)
      .firstOrNull;
}

String? _userName(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return provider.users
      .where((user) => user.id == card.userId)
      .map((user) => user.name)
      .firstOrNull;
}

String? _userIconKey(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return provider.users
      .where((user) => user.id == card.userId)
      .map((user) => user.iconKey)
      .firstOrNull;
}

String _cardLabel(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return '${provider.getCardName(cardId)} · •${card.lastFourDigits ?? '????'}';
}
