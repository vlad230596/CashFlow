import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/settings/cards_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/mcc_test_cache.dart';

void main() {
  testWidgets('card list shows one compact identity row per card',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = DataProvider(mccCacheStore: isolatedMccCache())
      ..banks = [
        BankModel(id: 1, name: 'Сбер', description: '', iconKey: 'sber')
      ]
      ..users = [UserModel(id: 1, name: 'Влад')]
      ..cards = [
        CardModel(
          id: 31,
          bankId: 1,
          userId: 1,
          paymentSystem: 'Мир',
          cardType: 'Virtual',
          lastFourDigits: '1248',
        ),
      ];

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: CardsSettingsScreen()),
    ));
    await tester.pump();

    expect(find.text('Влад Сбер · •1248'), findsOneWidget);
    expect(find.text('Мир · Virtual'), findsOneWidget);
    expect(find.textContaining('Bank:'), findsNothing);
    expect(find.byTooltip('Изменить карту'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
