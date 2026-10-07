import 'package:flutter/material.dart';

import '../../models/mcc_lookup_model.dart';
import '../../utils/identity_icons.dart';
import 'benefit_states_view.dart';
import 'offer_mcc_rules_section.dart';

/// Where a purchase with one MCC earns: the active offers whose bank category
/// lists the code, and how every bank treats it, exclusions included.
class MccPaymentOptionsView extends StatelessWidget {
  const MccPaymentOptionsView({
    super.key,
    required this.code,
    required this.lookup,
    required this.items,
    required this.onRetry,
    required this.onSelected,
  });

  final String code;
  final Future<MccLookupModel> lookup;
  final List<BenefitItemData> items;
  final VoidCallback onRetry;
  final ValueChanged<BenefitItemData> onSelected;

  @override
  Widget build(BuildContext context) => FutureBuilder<MccLookupModel>(
        future: lookup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              key: Key('benefit-mcc-loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Не удалось проверить MCC $code',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildResult(context, snapshot.data!);
        },
      );

  Widget _buildResult(BuildContext context, MccLookupModel lookup) {
    final textTheme = Theme.of(context).textTheme;
    final rules = {for (final rule in lookup.banks) rule.bankId: rule};
    final earning = items
        .where((item) =>
            rules[item.bankId]?.offerIds.contains(item.category.id) ?? false)
        .toList()
      ..sort((a, b) =>
          b.category.cashbackPercent.compareTo(a.category.cashbackPercent));

    // Banks with rules first, then banks of the family's cards without rules.
    final rows = <_BankRow>[
      for (final rule in lookup.banks)
        _BankRow(
          bankName: rule.bankName,
          bankIconKey: rule.bankIconKey,
          rule: rule,
          earns: earning.any((item) => item.bankId == rule.bankId),
          cards: items.where((item) => item.bankId == rule.bankId).toList(),
        ),
    ];
    final seen = {for (final rule in lookup.banks) rule.bankId};
    for (final item in items) {
      final bankId = item.bankId;
      if (bankId == null || !seen.add(bankId)) continue;
      rows.add(_BankRow(
        bankName: item.bankName ?? 'Банк',
        bankIconKey: item.bankIconKey,
        cards: items.where((other) => other.bankId == bankId).toList(),
      ));
    }

    return ListView(
      key: const Key('benefit-mcc-result'),
      padding: const EdgeInsets.fromLTRB(13, 4, 13, 24),
      children: [
        _MccHeader(mcc: lookup.mcc),
        const SizedBox(height: 14),
        if (earning.isNotEmpty) ...[
          Text('Повышенный кешбэк', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final item in earning)
            _EarningOfferRow(item: item, onTap: () => onSelected(item)),
        ] else
          Container(
            key: const Key('benefit-mcc-no-category'),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Код не входит ни в одну активную категорию ваших карт. '
              'Подойдёт карта с базовым кешбэком — ниже, как код учитывает '
              'каждый банк.',
            ),
          ),
        const SizedBox(height: 16),
        Text('Все банки', style: textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final row in rows) row,
        const SizedBox(height: 12),
        Text(
          'Справочно: банк может присвоить продавцу другой MCC, точный код '
          'видно в выписке после покупки.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MccHeader extends StatelessWidget {
  const _MccHeader({required this.mcc});

  final MccCodeModel mcc;

  @override
  Widget build(BuildContext context) {
    final description = mcc.description?.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MccCodeBadge(code: mcc.code),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mcc.title ?? 'Кода нет в справочнике MCC',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EarningOfferRow extends StatelessWidget {
  const _EarningOfferRow({required this.item, required this.onTap});

  final BenefitItemData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = item.category;
    final digits = item.lastFourDigits?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              BankIconBadge(
                iconKey: item.bankIconKey,
                bankName: item.bankName,
                size: 28,
              ),
              const SizedBox(width: 4),
              _OwnerBadge(item: item, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      [
                        item.bankName ?? item.cardLabel,
                        if (digits?.isNotEmpty == true) '•$digits',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${category.isStackableBonus ? '+' : ''}'
                '${_percent(category.cashbackPercent)}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFCF6500),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge({required this.item, required this.size});

  final BenefitItemData item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final marker = item.userMarker;
    if (marker == null) {
      return UserIconBadge(
        iconKey: item.userIconKey,
        userName: item.userName,
        size: size,
      );
    }
    return PersonMarkerBadge(
      marker: marker,
      userName: item.userName,
      size: size,
    );
  }
}

enum _Tone { positive, neutral, warning, negative }

/// One bank's verdict for the code, and whether a family card earns there.
class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.bankName,
    required this.cards,
    this.bankIconKey,
    this.rule,
    this.earns = false,
  });

  final String bankName;
  final String? bankIconKey;
  final MccBankRuleModel? rule;

  /// Whether an active offer on this bank's cards earns for the code.
  final bool earns;
  final List<BenefitItemData> cards;

  (String, _Tone) get _verdict {
    final rule = this.rule;
    if (rule == null) return ('Правила MCC банка не загружены', _Tone.neutral);
    final reason = rule.exclusion?.reason?.trim();
    final suffix = reason == null || reason.isEmpty ? '' : ' · $reason';
    final names = rule.categories.map((item) => '«${item.name}»').join(', ');
    final active = earns;
    return switch (rule.status) {
      'excluded' => (
          'В исключениях — кешбэк не начисляется$suffix',
          _Tone.negative
        ),
      'category_only' => (
          'Исключение: начисляется только в $names'
              '${active ? '' : ' — у вас не выбрана'}',
          active ? _Tone.positive : _Tone.warning,
        ),
      'conditional' => ('Условное исключение$suffix', _Tone.warning),
      'category' => (
          'Входит в $names${active ? '' : ' — у вас не выбрана'}',
          active ? _Tone.positive : _Tone.neutral,
        ),
      _ => (
          active
              ? 'Не входит в категории, начисляется по категории на все покупки'
              : 'Не входит в категории — базовый кешбэк',
          active ? _Tone.positive : _Tone.neutral,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (text, tone) = _verdict;
    final color = switch (tone) {
      _Tone.positive => const Color(0xFF168154),
      _Tone.neutral => colors.onSurfaceVariant,
      _Tone.warning => const Color(0xFFB36200),
      _Tone.negative => colors.error,
    };
    final icon = switch (tone) {
      _Tone.positive => Icons.check_circle_outline,
      _Tone.neutral => Icons.remove_circle_outline,
      _Tone.warning => Icons.error_outline,
      _Tone.negative => Icons.block,
    };
    final cardDigits = cards
        .map((item) => item.lastFourDigits?.trim())
        .whereType<String>()
        .where((digits) => digits.isNotEmpty)
        .map((digits) => '•$digits')
        .toSet();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BankIconBadge(iconKey: bankIconKey, bankName: bankName, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [bankName, ...cardDigits].join(' · '),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(icon, size: 15, color: color),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        text,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _percent(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
