import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashflow/screens/partner_offers_screen.dart';

void main() {
  testWidgets('uses public demo when the private snapshot is absent',
      (tester) async {
    rootBundle.evict('assets/partner_offers/offers.json');
    rootBundle.evict('assets/partner_offers/offers.example.json');
    tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key != 'assets/partner_offers/offers.example.json') return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
        'offers': [
          {
            'name': 'Демо магазин',
            'bankId': 'demo',
            'bankName': 'Демо банк',
            'description': 'Демонстрационные данные'
          }
        ],
      }))));
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
      rootBundle.evict('assets/partner_offers/offers.json');
      rootBundle.evict('assets/partner_offers/offers.example.json');
    });
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PartnerOffersScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Демо магазин'), findsOneWidget);
    expect(find.text('Демонстрационные данные'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('loads file offers and filters by source bank', (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/partner_offers/icons/test.png') {
        return ByteData.sublistView(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
      }
      if (key != 'assets/partner_offers/offers.json') return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
        'offers': [
          {
            'name': 'Магазин А',
            'bankId': 'alfa',
            'bankName': 'Альфа-Банк',
            'description': 'Покупки онлайн',
            'rateLabel': 'до 10%',
            'iconAsset': 'assets/partner_offers/icons/test.png',
            'validityLabel': 'До 30 сентября',
            'limits': ['Максимум — 400 рублей'],
            'requirements': ['Только для новых клиентов'],
            'conditions':
                'Только для новых клиентов\nКешбэк не начисляется за подарочные сертификаты',
          },
          {
            'name': 'Магазин Б',
            'bankId': 'sber',
            'bankName': 'Сбер',
            'description': '',
            'rateLabel': null
          },
        ],
      }))));
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null));
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PartnerOffersScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Магазин А'), findsOneWidget);
    expect(find.text('Магазин Б'), findsOneWidget);
    expect(find.text('до 10%'), findsOneWidget);
    expect(find.text('Ставка не указана'), findsOneWidget);
    expect(find.text('Срок действия: До 30 сентября'), findsOneWidget);
    expect(find.text('Максимум — 400 рублей'), findsOneWidget);
    expect(find.text('Только для новых клиентов'), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image).first).image,
        isA<AssetImage>());
    await tester.tap(find.widgetWithText(ChoiceChip, 'Сбер'));
    await tester.pumpAndSettle();
    expect(find.text('Магазин А'), findsNothing);
    expect(find.text('Магазин Б'), findsOneWidget);
    expect(find.text('Срок действия: не получен'), findsOneWidget);
    expect(find.text('Лимиты: не получены'), findsOneWidget);
    expect(find.text('Предложений: 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Все банки (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Магазин А'), findsOneWidget);
    final details =
        find.widgetWithText(TextButton, 'Все условия и ограничения').first;
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('подарочные сертификаты'));
  });
}
