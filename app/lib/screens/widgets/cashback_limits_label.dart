import 'package:flutter/material.dart';

class CashbackLimitsLabel extends StatelessWidget {
  const CashbackLimitsLabel({
    super.key,
    this.maxCashbackAmount,
    this.minPurchaseAmount,
    this.fontSize = 9,
  });

  final double? maxCashbackAmount;
  final double? minPurchaseAmount;
  final double fontSize;

  static String formatAmount(double amount) {
    final raw = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    final parts = raw.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match.group(1)} ',
    );
    return parts.length == 1 ? whole : '$whole,${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (maxCashbackAmount != null)
        'макс. ${formatAmount(maxCashbackAmount!)} ₽',
      if (minPurchaseAmount != null)
        'покупка от ${formatAmount(minPurchaseAmount!)} ₽',
    ];
    if (labels.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: labels.join('\n'),
      child: Text(
        labels.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
