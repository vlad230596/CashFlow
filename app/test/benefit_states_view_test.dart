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
