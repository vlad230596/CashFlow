import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/data_provider.dart';
import 'widgets/benefit_states_view.dart';

class CashbackScreen extends StatelessWidget {
  const CashbackScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final items = provider.effectiveActiveCashbackCategories
              .map(
                (category) => BenefitItemData(
                  category: category,
                  cardLabel: _cardLabel(provider, category.cardId),
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
          );
        },
      );
}

String _cardLabel(DataProvider provider, int cardId) {
  final card = provider.getCardById(cardId);
  return '${provider.getCardName(cardId)} ${card.lastFourDigits ?? '????'}';
}
