import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/data_provider.dart';
import '../../services/card_context.dart';
import '../../utils/identity_icons.dart';
import '../widgets/versioned_app_bar_title.dart';
import '../card_cashback_screen.dart';
import 'card_edit_screen.dart';

class CardsSettingsScreen extends StatelessWidget {
  const CardsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final catalog = CardContextCatalog(
      cards: dataProvider.cards,
      banks: dataProvider.banks,
      users: dataProvider.users,
    );
    final owners = dataProvider.users.map((user) => user.id);

    return Scaffold(
      appBar: AppBar(
        title: VersionedAppBarTitle(
          title: 'Карты (${dataProvider.cards.length})',
        ),
        actions: [
          IconButton(
            tooltip: 'Добавить карту',
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
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: dataProvider.cards.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, index) {
            final card = dataProvider.cards[index];
            final cardContext = catalog.forCard(card);
            final details = [
              if (card.paymentSystem?.trim().isNotEmpty == true)
                card.paymentSystem!.trim(),
              if (card.cardType?.trim().isNotEmpty == true)
                card.cardType!.trim(),
            ].join(' · ');
            // One line per card with the same bank and owner marks as
            // «Карты и категории».
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: card.id == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CardCashbackScreen(cardId: card.id!),
                        ),
                      ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BankIconBadge(
                    iconKey: cardContext.bankIconKey,
                    bankName: cardContext.bankName,
                    size: 28,
                  ),
                  const SizedBox(width: 4),
                  cardContext.ownerIconKey != null
                      ? UserIconBadge(
                          iconKey: cardContext.ownerIconKey,
                          userName: cardContext.ownerName,
                          size: 22,
                        )
                      : PersonMarkerBadge(
                          marker: personMarker(card.userId, owners),
                          userName: cardContext.ownerName,
                          size: 22,
                        ),
                ],
              ),
              title: Text(
                cardContext.benefitLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: details.isEmpty
                  ? null
                  : Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Semantics(
                container: true,
                identifier: 'edit-card-${card.id}',
                child: IconButton(
                  tooltip: 'Изменить карту',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            CardEditScreen(existingCard: card),
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
