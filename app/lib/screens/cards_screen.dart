import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../providers/data_provider.dart';
import '../services/card_cashback_overview.dart';
import '../services/card_context.dart';
import '../utils/cashback_period.dart';
import '../utils/cashflow_formatters.dart';
import '../utils/identity_icons.dart';
import 'card_cashback_screen.dart';

/// Every family card with the categories selected on it this month.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key, this.onShellDestinationSelected});

  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DataProvider>(context);
    final catalog = CardContextCatalog(
      cards: provider.cards,
      banks: provider.banks,
      users: provider.users,
    );
    final categories = provider.cashbackCategories.isNotEmpty
        ? provider.cashbackCategories
        : provider.activeCashbackCategories;
    final period = CashbackPeriod.month(provider.cashbackEffectiveDate);
    final query = _search.text.trim().toLowerCase();
    final owners = provider.users.map((user) => user.id);
    final rows = <({CardContext card, CardCashbackOverview overview})>[];
    for (final card in provider.cards) {
      if (card.id == null) continue;
      final cardContext = catalog.forCard(card);
      final overview = cardCashbackOverview(categories, card.id!, period);
      if (query.isNotEmpty &&
          !cardContext.benefitLabel.toLowerCase().contains(query) &&
          ![...overview.active, ...overview.pending]
              .any((item) => item.name.toLowerCase().contains(query))) {
        continue;
      }
      rows.add((card: cardContext, overview: overview));
    }
    rows.sort((a, b) => a.card.benefitLabel.compareTo(b.card.benefitLabel));

    return Scaffold(
      appBar: AppBar(title: const Text('Карты и категории')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: provider.fetchAllData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_outlined),
                      hintText: 'Карта, владелец или категория',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить поиск',
                              onPressed: () => setState(() => _search.clear()),
                              icon: const Icon(Icons.close_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Карты не найдены.',
                          textAlign: TextAlign.center),
                    ),
                  for (final row in rows)
                    _CardTile(
                      cardContext: row.card,
                      overview: row.overview,
                      marker: personMarker(row.card.card.userId, owners),
                      onTap: () => _open(row.card.card),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(CardModel card) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CardCashbackScreen(
            cardId: card.id!,
            onShellDestinationSelected: widget.onShellDestinationSelected,
          ),
        ),
      );
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.cardContext,
    required this.overview,
    required this.marker,
    required this.onTap,
  });

  final CardContext cardContext;
  final CardCashbackOverview overview;
  final PersonMarker marker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = [...overview.active, ...overview.pending]
      ..sort((a, b) => b.cashbackPercent.compareTo(a.cashbackPercent));
    final digits = cardContext.card.lastFourDigits?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BankIconBadge(
                    iconKey: cardContext.bankIconKey,
                    bankName: cardContext.bankName,
                    size: 32,
                  ),
                  const SizedBox(width: 6),
                  cardContext.ownerIconKey != null
                      ? UserIconBadge(
                          iconKey: cardContext.ownerIconKey,
                          userName: cardContext.ownerName,
                          size: 26,
                        )
                      : PersonMarkerBadge(
                          marker: marker,
                          userName: cardContext.ownerName,
                          size: 26,
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        cardContext.ownerAndBankLabel,
                        if (digits?.isNotEmpty == true) '•$digits',
                      ].join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              if (selected.isEmpty)
                Text(
                  'В этом месяце ничего не выбрано',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final category in selected)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: category.isActive
                            ? null
                            : const Icon(Icons.hourglass_empty, size: 14),
                        label: Text(
                          '${category.name} '
                          '${category.isStackableBonus ? '+' : ''}'
                          '${CashFlowFormatters.percent(category.cashbackPercent, suffix: false, decimalPlaces: null, decimalComma: false)}%',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
