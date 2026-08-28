import 'package:cash_app/screens/widgets/cashback_limits_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats cashback amounts with grouped thousands', () {
    expect(CashbackLimitsLabel.formatAmount(2000), '2 000');
    expect(CashbackLimitsLabel.formatAmount(1250.5), '1 250,5');
  });

  testWidgets('shows maximum cashback and minimum purchase separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CashbackLimitsLabel(
            maxCashbackAmount: 2000,
            minPurchaseAmount: 5000,
          ),
        ),
      ),
    );

    expect(find.text('макс. 2 000 ₽ · покупка от 5 000 ₽'), findsOneWidget);
  });
}
