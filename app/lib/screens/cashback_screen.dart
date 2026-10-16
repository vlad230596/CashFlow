import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/data_provider.dart';
import '../services/card_context.dart';
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
          final contexts = CardContextCatalog(
              cards: provider.cards,
              banks: provider.banks,
              users: provider.users);
          final items = provider.effectiveActiveCashbackCategories.map(
            (category) {
              final context = contexts.forId(category.cardId);
              return BenefitItemData(
                  category: category,
                  cardLabel: context.benefitLabel,
                  bankId: context.card.bankId,
                  bankName: context.bankName,
                  bankIconKey: context.bankIconKey,
                  userName: context.ownerName,
                  userIconKey: context.ownerIconKey,
                  lastFourDigits: context.card.lastFourDigits);
            },
          ).toList();
          return BenefitStatesView(
            phase: provider.primaryDataPhase,
            hasUsableSnapshot: provider.hasUsableDataSnapshot ||
                provider.mccOfflineReady ||
                provider.mccCatalog.isNotEmpty,
            snapshotUpdatedAt:
                provider.dataSnapshotUpdatedAt ?? provider.mccSnapshotUpdatedAt,
            items: items,
            canonicalCategories: provider.canonicalCategories,
            mccResults: [
              for (final mcc in provider.mccCatalog)
                BenefitMccSearchResult(
                  code: mcc.code,
                  name: mcc.title ?? 'MCC ${mcc.code}',
                  description: 'Где начислят кешбэк',
                ),
            ],
            onLookupMcc: provider.lookupMcc,
            mccDataRevision: provider.mccDataRevision,
            mccContextIdentity: provider.mccContextIdentity,
            onRefresh: () async {
              await provider.fetchAllData();
            },
            onShellDestinationSelected: onShellDestinationSelected,
            onInternalDetailChanged: onInternalDetailChanged,
          );
        },
      );
}
