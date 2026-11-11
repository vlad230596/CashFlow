import 'package:flutter/material.dart';

import '../../models/card_balance_model.dart';
import '../../utils/cashflow_formatters.dart';

/// Card balance with the time ZenMoney data was obtained.
///
/// The amount and its freshness are one text, so a balance is never shown
/// without its timestamp. Outdated data (older than six hours, a cached copy
/// while offline, or a server that cannot refresh) is muted with a history
/// icon instead of looking current.
class CardBalanceLabel extends StatelessWidget {
  const CardBalanceLabel({
    super.key,
    required this.view,
    this.fontSize = 11,
    this.onDark = false,
    this.now,
  });

  final CardBalanceView view;
  final double fontSize;

  /// White text for the gradient "best option" card.
  final bool onDark;

  /// Injected clock for tests; defaults to [DateTime.now].
  final DateTime? now;

  static String amountText(CardBalance balance) {
    if (balance.isCredit) {
      return 'доступно ${moneyLabel(balance.available, balance.currency)} '
          'с кредитным лимитом';
    }
    return 'на карте ${moneyLabel(balance.balance, balance.currency)}';
  }

  @override
  Widget build(BuildContext context) {
    final current = now ?? DateTime.now();
    final balance = view.balance;
    final stale = view.isStale(current);
    final colors = Theme.of(context).colorScheme;
    final freshness = [
      freshnessLabel(balance.fetchedAt, current),
      if (view.offline) 'сохранённая копия',
    ].join(' · ');
    final Color amountColor;
    final Color metaColor;
    if (onDark) {
      amountColor = stale ? const Color(0xB3FFFFFF) : Colors.white;
      metaColor = stale ? const Color(0xFFFFD27A) : const Color(0xFFDCEAFF);
    } else {
      amountColor = stale ? colors.onSurfaceVariant : colors.onSurface;
      metaColor = stale ? const Color(0xFF9A5A00) : colors.onSurfaceVariant;
    }
    final amount = amountText(balance);
    return Semantics(
      container: true,
      label: '${stale ? 'Возможно, устарело: ' : ''}$amount, $freshness',
      child: ExcludeSemantics(
        child: Row(
          key: ValueKey('card-balance-${balance.cardId}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 4),
              child: Icon(
                stale ? Icons.history : Icons.account_balance_wallet_outlined,
                key: stale
                    ? ValueKey('card-balance-stale-${balance.cardId}')
                    : null,
                size: fontSize + 2,
                color: metaColor,
              ),
            ),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: amount,
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · $freshness',
                      style: TextStyle(color: metaColor),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
