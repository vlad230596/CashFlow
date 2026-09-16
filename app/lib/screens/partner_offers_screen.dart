import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/partner_offer_model.dart';

class PartnerOffersScreen extends StatefulWidget {
  const PartnerOffersScreen({super.key});

  @override
  State<PartnerOffersScreen> createState() => _PartnerOffersScreenState();
}

class _PartnerOffersScreenState extends State<PartnerOffersScreen> {
  late final Future<List<PartnerOffer>> _offers = rootBundle
      .loadString('assets/partner_offers/offers.json')
      .catchError((Object error) =>
          rootBundle.loadString('assets/partner_offers/offers.example.json'))
      .then(PartnerOffer.parse);
  String? _bank;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PartnerOffer>>(
        future: _offers,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
                child: Text('Не удалось загрузить файл предложений.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final banks = {for (final offer in all) offer.bankId: offer.bankName};
          final visible = all
              .where((offer) => _bank == null || offer.bankId == _bank)
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Эксперимент · Индивидуальные предложения',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                        'Сохранённая выгрузка Chrome. Ставки и доступность могли измениться.'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      ChoiceChip(
                          label: Text('Все банки (${all.length})'),
                          selected: _bank == null,
                          onSelected: (_) => setState(() => _bank = null)),
                      for (final bank in banks.entries)
                        ChoiceChip(
                            label: Text(bank.value),
                            selected: _bank == bank.key,
                            onSelected: (selected) => setState(
                                () => _bank = selected ? bank.key : null)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Предложений: ${visible.length}'),
                  ]),
            ),
            Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('В файле пока нет предложений.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _OfferCard(offer: visible[index]),
                      )),
          ]);
        },
      );
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});
  final PartnerOffer offer;

  void _showConditions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(offer.name, style: Theme.of(context).textTheme.titleLarge),
              Text(offer.bankName),
              const SizedBox(height: 16),
              Text('Срок действия: ${offer.validityLabel ?? 'не получен'}'),
              const SizedBox(height: 12),
              const Text('Лимиты',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              for (final limit in offer.limits) Text(limit),
              if (offer.limits.isEmpty)
                const Text('Лимиты не получены. Проверьте правила акции.'),
              const SizedBox(height: 12),
              const Text('Полные условия',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (offer.conditionsFromHistory) Text(_historyLabel(offer)),
              const SizedBox(height: 8),
              SelectableText(offer.conditions.isEmpty
                  ? 'Подробные условия не получены.'
                  : offer.conditions),
            ]),
          ),
        ),
      ),
    );
  }

  String _historyLabel(PartnerOffer offer) {
    final date = offer.conditionsCollectedAt?.toLocal();
    return 'Условия из предыдущей выгрузки${date == null ? '' : ' от ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}'}';
  }

  @override
  Widget build(BuildContext context) {
    final date = offer.collectedAt?.toLocal();
    final fallback = Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.storefront_outlined));
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: offer.iconAsset != null
                  ? Image.asset(offer.iconAsset!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => fallback)
                  : offer.iconUrl != null
                      ? Image.network(offer.iconUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => fallback)
                      : fallback,
            )),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(offer.name, style: Theme.of(context).textTheme.titleMedium),
          Text(offer.bankName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(offer.rateLabel ?? 'Ставка не указана',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          Text(
              offer.description.isEmpty
                  ? 'Описание не получено'
                  : offer.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Text('Срок действия: ${offer.validityLabel ?? 'не получен'}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (offer.limits.isEmpty)
            const Text('Лимиты: не получены')
          else
            for (final limit in offer.limits) Text(limit),
          if (offer.requirements.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final requirement in offer.requirements.take(2))
              Text(requirement),
          ],
          if (offer.conditionsFromHistory) ...[
            const SizedBox(height: 6),
            Text(_historyLabel(offer),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          TextButton(
            onPressed: () => _showConditions(context),
            child: const Text('Все условия и ограничения'),
          ),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(
                'Собрано ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ])),
      ]),
    ));
  }
}
