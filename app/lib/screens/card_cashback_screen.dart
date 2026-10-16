import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';
import '../services/card_cashback_overview.dart';
import '../services/card_context.dart';
import '../utils/cashback_period.dart';
import '../utils/category_info.dart';
import '../utils/cashflow_formatters.dart';
import '../utils/identity_icons.dart';
import 'cashback_category_detail_screen.dart';
import 'widgets/cashback_limits_label.dart';

const _monthNames = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

/// Categories chosen for one card: what works now, what still waits for the
/// bank, and what else the bank offered for the month.
class CardCashbackScreen extends StatefulWidget {
  const CardCashbackScreen({
    super.key,
    required this.cardId,
    this.highlightCategoryId,
    this.onShellDestinationSelected,
  });

  final int cardId;

  /// The category the user came from; it is marked in the list.
  final int? highlightCategoryId;
  final ValueChanged<int>? onShellDestinationSelected;

  @override
  State<CardCashbackScreen> createState() => _CardCashbackScreenState();
}

class _CardCashbackScreenState extends State<CardCashbackScreen> {
  DateTime? _month;
  bool _showAvailable = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DataProvider>(context);
    final cardContext = CardContextCatalog(
      cards: provider.cards,
      banks: provider.banks,
      users: provider.users,
    ).forId(widget.cardId);
    final categories = provider.cashbackCategories.isNotEmpty
        ? provider.cashbackCategories
        : provider.activeCashbackCategories;
    final today = provider.cashbackEffectiveDate;
    final months = cardCashbackMonths(categories, widget.cardId, today);
    final month = months.contains(_month) ? _month! : months.first;
    final overview = cardCashbackOverview(
      categories,
      widget.cardId,
      CashbackPeriod.month(month),
    );
    final digits = cardContext.card.lastFourDigits?.trim();
    final title = digits?.isNotEmpty == true ? 'Карта •$digits' : 'Карта';
    final owners = provider.users.map((user) => user.id);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                  _CardHeader(
                    cardContext: cardContext,
                    marker: personMarker(cardContext.card.userId, owners),
                  ),
                  const SizedBox(height: 16),
                  if (months.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in months)
                          ChoiceChip(
                            label: Text(_monthLabel(item, today)),
                            selected: item == month,
                            onSelected: (_) => setState(() => _month = item),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _monthLabel(month, today),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  if (!overview.hasSelection)
                    _EmptySelection(
                      hasAvailable: overview.available.isNotEmpty,
                    ),
                  if (overview.active.isNotEmpty)
                    _Section(
                      title: 'Действует',
                      subtitle: 'Выбрано и подтверждено банком',
                      icon: Icons.verified_outlined,
                      categories: overview.active,
                      highlightId: widget.highlightCategoryId,
                      onOpen: _open,
                    ),
                  if (overview.pending.isNotEmpty)
                    _Section(
                      title: 'Выбрано в плане',
                      subtitle: 'Банк ещё не подтвердил выбор',
                      icon: Icons.hourglass_empty_outlined,
                      categories: overview.pending,
                      highlightId: widget.highlightCategoryId,
                      onOpen: _open,
                    ),
                  if (overview.available.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showAvailable = !_showAvailable),
                      icon: Icon(_showAvailable
                          ? Icons.expand_less
                          : Icons.expand_more),
                      label: Text(
                        '${_showAvailable ? 'Скрыть' : 'Показать'} '
                        'невыбранные · ${overview.available.length}',
                      ),
                    ),
                    if (_showAvailable)
                      _Section(
                        title: 'Не выбрано',
                        subtitle: 'Банк предлагал, но в план не вошло',
                        icon: Icons.radio_button_unchecked,
                        categories: overview.available,
                        highlightId: widget.highlightCategoryId,
                        onOpen: _open,
                      ),
                  ],
                  if (widget.onShellDestinationSelected != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        widget.onShellDestinationSelected!(1);
                      },
                      icon: const Icon(Icons.event_note_outlined),
                      label: const Text('Изменить выбор в плане'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(CashbackCategoryModel category) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CashbackCategoryDetailScreen(
            category: category,
            onShellDestinationSelected: widget.onShellDestinationSelected,
            showCardSelection: false,
          ),
        ),
      );
}

String _monthLabel(DateTime month, DateTime today) {
  final name = _monthNames[month.month - 1];
  final label = month.year == today.year ? name : '$name ${month.year}';
  if (month.year == today.year && month.month == today.month) {
    return '$label · сейчас';
  }
  return label;
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.cardContext, required this.marker});

  final CardContext cardContext;
  final PersonMarker marker;

  @override
  Widget build(BuildContext context) {
    final card = cardContext.card;
    final kind = [card.paymentSystem, card.cardType]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    return Row(
      children: [
        BankIconBadge(
          iconKey: cardContext.bankIconKey,
          bankName: cardContext.bankName,
          size: 44,
        ),
        const SizedBox(width: 8),
        cardContext.ownerIconKey != null
            ? UserIconBadge(
                iconKey: cardContext.ownerIconKey,
                userName: cardContext.ownerName,
                size: 36,
              )
            : PersonMarkerBadge(
                marker: marker,
                userName: cardContext.ownerName,
                size: 36,
              ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cardContext.ownerAndBankLabel,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (kind.isNotEmpty)
                Text(kind, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection({required this.hasAvailable});

  final bool hasAvailable;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const ExcludeSemantics(child: Icon(Icons.info_outline)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasAvailable
                      ? 'На этот месяц по карте ничего не выбрано.'
                      : 'По карте нет категорий на этот месяц.',
                ),
              ),
            ],
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.categories,
    required this.highlightId,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<CashbackCategoryModel> categories;
  final int? highlightId;
  final ValueChanged<CashbackCategoryModel> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Row(
                  children: [
                    ExcludeSemantics(child: Icon(icon, size: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$title · ${categories.length}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < categories.length; index++) ...[
                    if (index > 0) const Divider(height: 1),
                    _CategoryRow(
                      category: categories[index],
                      highlighted: categories[index].id == highlightId,
                      onTap: () => onOpen(categories[index]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.highlighted,
    required this.onTap,
  });

  final CashbackCategoryModel category;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = CategoryInfo.getCategoryColor(category.name);
    final colors = Theme.of(context).colorScheme;
    final kind = category.isStackableBonus
        ? 'Суммируется с категориями'
        : category.isTaskBonus
            ? 'За задание'
            : null;
    return Material(
      color: highlighted ? colors.secondaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child:
              Icon(CategoryInfo.getCategoryIcon(category.name), color: color),
        ),
        title: Text(
          category.name,
          style:
              highlighted ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (highlighted) const Text('Вы пришли из этой категории'),
            if (kind != null) Text(kind),
            Text(_periodLabel(category)),
            CashbackLimitsLabel(
              maxCashbackAmount: category.maxCashbackAmount,
              minPurchaseAmount: category.minPurchaseAmount,
            ),
          ],
        ),
        trailing: Text(
          '${category.isStackableBonus ? '+' : ''}'
          '${CashFlowFormatters.percent(category.cashbackPercent, suffix: false, decimalPlaces: null, decimalComma: false)}%',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

String _periodLabel(CashbackCategoryModel category) {
  String date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}';
  final end = category.endDate;
  // Stored ends are either an exclusive midnight or the last moment of a day.
  final lastDay = end.hour == 0 && end.minute == 0 && end.second == 0
      ? end.subtract(const Duration(days: 1))
      : end;
  return '${date(category.startDate)} – ${date(lastDay)}';
}
