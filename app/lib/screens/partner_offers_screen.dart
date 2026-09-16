import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/partner_offer_model.dart';
import '../providers/data_provider.dart';

class PartnerOffersScreen extends StatefulWidget {
  const PartnerOffersScreen({super.key});

  @override
  State<PartnerOffersScreen> createState() => _PartnerOffersScreenState();
}

class _PartnerOffersScreenState extends State<PartnerOffersScreen> {
  int? _bankId;
  bool _showHidden = false;

  Future<void> _changeMode(DataProvider provider, bool hidden) async {
    setState(() {
      _showHidden = hidden;
      _bankId = null;
    });
    await provider.fetchPartnerOffers(rating: hidden ? 'hidden' : null);
  }

  @override
  Widget build(BuildContext context) => Consumer<DataProvider>(
        builder: (context, provider, _) {
          final modeOffers = provider.partnerOffers.where((offer) => _showHidden
              ? offer.preference == 'hidden'
              : offer.preference != 'hidden');
          final banks = {
            for (final offer in modeOffers) offer.bankId: offer.bankName,
          };
          final visible = modeOffers
              .where((offer) => _bankId == null || offer.bankId == _bankId)
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Интересные и отложенные'),
                          selected: !_showHidden,
                          onSelected: (_) => _changeMode(provider, false),
                        ),
                        ChoiceChip(
                          label: const Text('Чёрный список'),
                          selected: _showHidden,
                          onSelected: (_) => _changeMode(provider, true),
                        ),
                      ],
                    ),
                    if (banks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('Все (${modeOffers.length})'),
                              selected: _bankId == null,
                              onSelected: (_) => setState(() => _bankId = null),
                            ),
                            const SizedBox(width: 8),
                            for (final bank in banks.entries) ...[
                              ChoiceChip(
                                label: Text(bank.value),
                                selected: _bankId == bank.key,
                                onSelected: (selected) => setState(
                                    () => _bankId = selected ? bank.key : null),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (provider.partnerOffersError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${provider.partnerOffersError}. Показан сохранённый список.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (provider.partnerOffersLoading)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => provider.fetchPartnerOffers(
                    rating: _showHidden ? 'hidden' : null,
                  ),
                  child: visible.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height / 3,
                              child: Center(
                                child: Text(
                                  _showHidden
                                      ? 'Чёрный список пуст.'
                                      : 'Нет доступных предложений.',
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                          itemCount: visible.length,
                          itemBuilder: (context, index) => _OfferCard(
                            offer: visible[index],
                            onPreference: (rating) => _setPreference(
                                provider, visible[index], rating),
                            onDetails: () =>
                                _showDetails(provider, visible[index]),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _setPreference(
    DataProvider provider,
    PartnerOffer offer,
    String rating,
  ) async {
    final previous = offer.preference;
    try {
      await provider.updatePartnerOfferPreference(offer.id, rating);
      if (!mounted || rating != 'hidden') return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Предложение добавлено в чёрный список.'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () =>
                provider.updatePartnerOfferPreference(offer.id, previous),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить оценку: $error')),
      );
    }
  }

  void _showDetails(DataProvider provider, PartnerOffer offer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: FutureBuilder<PartnerOffer>(
            future: provider.fetchPartnerOfferDetails(offer.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Text('Не удалось загрузить условия: ${snapshot.error}'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _OfferDetails(offer: snapshot.data!);
            },
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.onPreference,
    required this.onDetails,
  });

  final PartnerOffer offer;
  final ValueChanged<String> onPreference;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OfferLogo(url: offer.iconUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                offer.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                offer.bankName,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        _OfferMenu(
                          preference: offer.preference,
                          onSelected: onPreference,
                          onDetails: onDetails,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _InfoBadge(
                          icon: Icons.percent,
                          text: offer.rateLabel ?? 'Ставка не указана',
                          color: colors.primaryContainer,
                        ),
                        for (final limit in offer.limits.take(2))
                          _InfoBadge(
                            icon: Icons.account_balance_wallet_outlined,
                            text: limit.originalText,
                            color: colors.secondaryContainer,
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _deadlineLabel(offer, DateTime.now()),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _isEndingSoon(offer, DateTime.now())
                            ? colors.error
                            : colors.onSurface,
                      ),
                    ),
                    if (offer.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        offer.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Обновлено ${_formatDate(offer.collectedAt.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferMenu extends StatelessWidget {
  const _OfferMenu({
    required this.preference,
    required this.onSelected,
    required this.onDetails,
  });

  final String preference;
  final ValueChanged<String> onSelected;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Действия с предложением',
        onSelected: (value) {
          if (value == 'details') {
            onDetails();
          } else {
            onSelected(value);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'interesting', child: Text('Интересно')),
          const PopupMenuItem(value: 'undecided', child: Text('Отложить')),
          PopupMenuItem(
            value: preference == 'hidden' ? 'undecided' : 'hidden',
            child: Text(
              preference == 'hidden' ? 'Восстановить' : 'В чёрный список',
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'details', child: Text('Подробнее')),
        ],
      );
}

class _OfferLogo extends StatelessWidget {
  const _OfferLogo({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.storefront_outlined)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 4),
            Flexible(child: Text(text)),
          ],
        ),
      );
}

class _OfferDetails extends StatelessWidget {
  const _OfferDetails({required this.offer});
  final PartnerOffer offer;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(offer.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(offer.bankName),
            const SizedBox(height: 16),
            Text(
              _deadlineLabel(offer, DateTime.now()),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Лимиты', style: TextStyle(fontWeight: FontWeight.bold)),
            if (offer.limits.isEmpty)
              const Text('Не получены')
            else
              for (final limit in offer.limits) Text('• ${limit.originalText}'),
            if (offer.requirements.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Требования и ограничения',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final requirement in offer.requirements)
                Text('• $requirement'),
            ],
            if (offer.steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Как получить',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (var index = 0; index < offer.steps.length; index++)
                Text('${index + 1}. ${offer.steps[index]}'),
            ],
            const SizedBox(height: 16),
            const Text('Полные условия',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SelectableText(
              offer.conditions.isEmpty
                  ? 'Подробные условия не получены.'
                  : offer.conditions,
            ),
            const SizedBox(height: 16),
            Text(
              'Данные получены ${_formatDate(offer.collectedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

String _deadlineLabel(PartnerOffer offer, DateTime now) {
  final end = offer.endsAt?.toLocal();
  if (end == null) {
    return offer.validityLabel == null
        ? 'Срок не указан в источнике'
        : 'Срок: ${offer.validityLabel}';
  }
  final today = DateTime(now.year, now.month, now.day);
  final endDay = DateTime(end.year, end.month, end.day);
  final days = endDay.difference(today).inDays;
  if (days < 0) return 'Завершено';
  if (days == 0) return 'Последний день · до ${_formatDate(end)}';
  return 'Осталось ${_daysLabel(days)} · до ${_formatDate(end)}';
}

bool _isEndingSoon(PartnerOffer offer, DateTime now) {
  final end = offer.endsAt?.toLocal();
  if (end == null) return false;
  final days = DateTime(end.year, end.month, end.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  return days >= 0 && days <= 3;
}

String _daysLabel(int days) {
  final lastTwo = days % 100;
  final last = days % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return '$days дней';
  if (last == 1) return '$days день';
  if (last >= 2 && last <= 4) return '$days дня';
  return '$days дней';
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';
