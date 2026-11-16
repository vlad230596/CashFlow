import 'package:flutter/material.dart';

import '../../models/planned_payment_model.dart';
import '../../utils/cashflow_formatters.dart';

/// «Чем оплатить»: the card that earns most for a payment's MCC on its due
/// date, or why there is no hint. The answer comes from the server with the
/// payment ([PaymentCardSuggestion]); this widget only renders it.
class PaymentCardSuggestionView extends StatelessWidget {
  const PaymentCardSuggestionView({
    super.key,
    required this.suggestion,
    required this.cardLabel,
  });

  final PaymentCardSuggestion suggestion;

  /// Display name of a card (owner, bank, last digits) from local data.
  final String Function(PaymentCardOption option) cardLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final day = calendarDateLabel(suggestion.asOf);
    final best = suggestion.best;
    if (best == null) {
      final text = switch (suggestion.status) {
        PaymentCardSuggestionStatus.noRules =>
          'Правила банков для MCC ${suggestion.mccCode} на $day не загружены — '
              'подсказки нет.',
        _ => 'Нет повышенного кешбэка по MCC ${suggestion.mccCode} на $day: '
            'подойдёт карта с базовым кешбэком.',
      };
      return Container(
        key: const ValueKey('payment-card-suggestion-none'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: textTheme.bodyMedium),
      );
    }
    return Card(
      key: const ValueKey('payment-card-suggestion'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Выгоднее оплатить', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.credit_score_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cardLabel(best),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '«${best.categoryName}» · MCC ${suggestion.mccCode}'
                        ' · на $day',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  paymentCardPercentLabel(best),
                  style: textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFCF6500),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (suggestion.alternatives.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Ещё: ${suggestion.alternatives.map((option) => '${cardLabel(option)} '
                    '${paymentCardPercentLabel(option)}').join('; ')}',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String paymentCardPercentLabel(PaymentCardOption option) =>
    '${option.isStackableBonus ? '+' : ''}'
    '${CashFlowFormatters.percent(option.cashbackPercent)}';
