import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/widgets/benefit_states_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact layout opens details in the same content area',
      (tester) async {
    await _setViewport(tester, const Size(390, 800));
    await tester.pumpWidget(_app(items: _items));

    expect(find.byKey(const Key('benefit-compact-list')), findsOneWidget);
    expect(find.text('Аптеки'), findsOneWidget);

    await tester.tap(find.text('Аптеки'));
    await tester.pump();

    expect(find.byKey(const Key('benefit-compact-detail')), findsOneWidget);
    expect(find.text('К результатам'), findsOneWidget);
    expect(find.text('Результат справочный и не меняет выбранный план.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout keeps master and detail visible',
      (tester) async {
    await _setViewport(tester, const Size(1100, 800));
    await tester.pumpWidget(_app(items: _items));

    expect(find.byKey(const Key('benefit-expanded-layout')), findsOneWidget);
    expect(find.text('Выберите категорию'), findsOneWidget);

    await tester.tap(find.text('Аптеки'));
    await tester.pump();

    expect(find.byKey(const Key('benefit-expanded-layout')), findsOneWidget);
    expect(find.text('Выберите категорию'), findsNothing);
    expect(find.text('К результатам'), findsNothing);
    expect(find.text('Карта семьи •1234'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('error without snapshot offers retry', (tester) async {
    await _setViewport(tester, const Size(390, 800));
    var retryCount = 0;
    await tester.pumpWidget(_app(
      phase: PrimaryDataPhase.failed,
      hasUsableSnapshot: false,
      items: const [],
      onRefresh: () async => retryCount++,
    ));

    expect(find.byKey(const Key('benefit-error-state')), findsOneWidget);
    expect(find.text('Не удалось загрузить данные'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();

    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text remains readable without layout exceptions',
      (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(items: _items, textScale: 2));

    expect(find.text('Выгода'), findsOneWidget);
    expect(find.text('Аптеки'), findsOneWidget);
    expect(find.text('Карта семьи •1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact search groups categories, MCC codes and merchants',
      (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        items: _searchItems,
        mccResults: _mccResults,
        merchantResults: _merchantResults,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('benefit-search')),
      'дет',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('benefit-compact-search-results')),
      findsOneWidget,
    );
    expect(find.text('КАТЕГОРИИ'), findsOneWidget);
    expect(find.text('MCC-КОДЫ'), findsOneWidget);
    expect(find.text('МАГАЗИНЫ'), findsOneWidget);
    expect(find.text('Детские товары'), findsOneWidget);
    expect(find.text('Детская одежда'), findsOneWidget);
    expect(find.text('Детский мир'), findsOneWidget);

    await tester.tap(find.text('Детский мир'));
    await tester.pump();

    expect(
      find.byKey(const Key('benefit-compact-purchase-result')),
      findsOneWidget,
    );
    expect(find.text('ЛУЧШИЙ ИЗВЕСТНЫЙ ВАРИАНТ'), findsOneWidget);
    expect(find.text('Т-Банк • 5678'), findsOneWidget);
    expect(find.textContaining('Точный MCC будущей покупки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact overview shows recent merchants and opens result',
      (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(items: _searchItems, merchantResults: _merchantResults),
    );

    expect(find.text('Недавние магазины'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Детский мир'), findsOneWidget);

    await tester.tap(find.text('Детский мир'));
    await tester.pump();

    expect(
      find.byKey(const Key('benefit-compact-purchase-result')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({
  PrimaryDataPhase phase = PrimaryDataPhase.ready,
  bool hasUsableSnapshot = true,
  List<BenefitItemData> items = const [],
  List<BenefitMccSearchResult> mccResults = const [],
  List<BenefitMerchantSearchResult> merchantResults = const [],
  Future<void> Function()? onRefresh,
  double textScale = 1,
}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: BenefitStatesView(
          phase: phase,
          hasUsableSnapshot: hasUsableSnapshot,
          snapshotUpdatedAt: DateTime(2026, 9, 22, 10, 42),
          items: items,
          mccResults: mccResults,
          merchantResults: merchantResults,
          onRefresh: onRefresh ?? () async {},
        ),
      ),
    );

final _items = [
  BenefitItemData(
    category: CashbackCategoryModel(
      id: 1,
      name: 'Аптеки',
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 10),
      isSelected: true,
      isBankConfirmed: true,
      cashbackPercent: 5,
      cardId: 1,
      description: 'Начисление действует при оплате покупки картой.',
      maxCashbackAmount: 2000,
    ),
    cardLabel: 'Карта семьи •1234',
  ),
  BenefitItemData(
    category: CashbackCategoryModel(
      id: 2,
      name: 'Супермаркеты',
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 10),
      isSelected: true,
      isBankConfirmed: true,
      cashbackPercent: 3,
      cardId: 2,
    ),
    cardLabel: 'Основная карта •5678',
  ),
];

final _searchItems = [
  BenefitItemData(
    category: CashbackCategoryModel(
      id: 3,
      name: 'Детские товары',
      startDate: DateTime(2026, 9),
      endDate: DateTime(2026, 10),
      isSelected: true,
      isBankConfirmed: true,
      cashbackPercent: 5,
      cardId: 1,
    ),
    cardLabel: 'Альфа-Банк •1234',
  ),
];

const _mccResults = [
  BenefitMccSearchResult(
    code: '5641',
    name: 'Детская одежда',
    description: 'Children’s and Infants’ Wear Stores',
  ),
  BenefitMccSearchResult(
    code: '5945',
    name: 'Игрушки и товары для хобби',
    description: 'Hobby, Toy and Game Shops',
  ),
];

const _merchantResults = [
  BenefitMerchantSearchResult(
    name: 'Детский мир',
    description: '7 операций · наблюдались MCC 5945 и 5641',
    initials: 'ДМ',
    highlighted: true,
    purchaseResult: BenefitPurchaseResult(
      title: 'Покупка в «Детском мире»',
      merchantName: 'Детский мир',
      subtitle: 'По истории семьи возможны два MCC',
      evidence: ['5945 · 5 из 7 операций', '5641 · 2 из 7'],
      best: BenefitPurchaseOption(
        bankMark: 'Т',
        cardLabel: 'Т-Банк • 5678',
        cardSubtitle: 'Общая карта',
        rate: '7%',
        categoryName: 'Развлечения',
        categorySubtitle: 'Уже выбрано и подтверждено',
        limitLabel: 'до 3 000 ₽',
        reason: 'Почему: MCC 5945 чаще всего встречался в ваших операциях '
            'и явно входит в правило «Развлечения» этого банка.',
        chainLabel: 'Т-Банк',
        bankColor: Color(0xFF111111),
      ),
      alternatives: [
        BenefitPurchaseOption(
          bankMark: 'A',
          cardLabel: 'Альфа-Банк • 1234',
          cardSubtitle: 'Карта Анны',
          rate: '5%',
          categoryName: 'Детские товары',
          categorySubtitle: 'Выбрано',
          matchLabel: 'MCC 5945 подходит',
        ),
        BenefitPurchaseOption(
          bankMark: 'ВТБ',
          cardLabel: 'ВТБ • 3456',
          cardSubtitle: 'Карта Влада',
          rate: '5%',
          categoryName: 'Детские товары',
          categorySubtitle: 'Выбрано',
          matchLabel: 'MCC 5945 не покрывается',
          matchIsPositive: false,
          bankColor: Color(0xFF1684BB),
        ),
      ],
      risk: 'Если операция пройдёт с MCC 5641, лучший вариант может '
          'измениться. Точный MCC будущей покупки заранее неизвестен.',
    ),
  ),
  BenefitMerchantSearchResult(
    name: 'Детский развлекательный центр',
    description: '2 операции · наблюдался MCC 7999',
    initials: 'ДР',
    color: Color(0xFF7957BA),
  ),
];
