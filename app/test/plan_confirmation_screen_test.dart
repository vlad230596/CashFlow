import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/plan_confirmation_screen.dart';
import 'package:cashflow/services/app_session_type.dart';
import 'package:cashflow/services/cashback_import_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('compact overview opens snapshot sheet without changing plan',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _provider(role: 'editor');
    await _pump(tester, provider);

    expect(find.text('План — это ещё не активация'), findsOneWidget);
    expect(find.text('1 из 2'), findsOneWidget);
    expect(find.text('Первый банк · 1111'), findsOneWidget);
    expect(find.text('Есть расхождение'), findsOneWidget);
    expect(find.text('Подтверждение'), findsOneWidget);
    expect(find.text('План'), findsWidgets);
    expect(find.text('Выгода'), findsOneWidget);

    await tester.tap(find.text('Первый банк · 1111'));
    await tester.pumpAndSettle();

    expect(find.text('Импортировать снимок'), findsOneWidget);
    expect(find.text('Выбрать JSON-файл'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Первый банк · 1111'), findsWidgets);
    expect(
        provider.cashbackCategories.every((item) => item.isSelected), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact completed card opens confirmation details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _provider(role: 'editor');
    provider.cashbackCategories = [
      for (final category in provider.cashbackCategories)
        category.isSelectable
            ? category.copyWith(isBankConfirmed: true)
            : category,
    ];
    await _pump(tester, provider);

    await tester.tap(find.text('Первый банк · 1111'));
    await tester.pumpAndSettle();

    expect(find.text('Подтверждения'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('План — это ещё не активация'), findsNothing);
    expect(find.text('Подтверждено банком'), findsNWidgets(2));
    expect(find.text('Импортировать снимок'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout keeps list details and summary visible',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, _provider(role: 'editor'));

    expect(find.text('Первый банк · 1111'), findsNWidgets(2));
    expect(find.text('Сводка месяца'), findsOneWidget);
    expect(find.text('Источник подтверждения'), findsOneWidget);
    expect(
      find.text('Импортировать снимок', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium selection survives resize to expanded', (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, _provider(role: 'editor'));
    expect(find.text('Сводка месяца'), findsNothing);

    await tester.tap(find.text('Первый банк · 1111'));
    await tester.pumpAndSettle();
    expect(find.text('АЗС'), findsOneWidget);

    tester.view.physicalSize = const Size(1100, 900);
    await tester.pumpAndSettle();

    expect(find.text('Первый банк · 1111'), findsNWidgets(2));
    expect(find.text('АЗС'), findsOneWidget);
    expect(find.text('Сводка месяца'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact layout supports enlarged text without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, _provider(role: 'editor'));

    expect(find.text('План — это ещё не активация'), findsOneWidget);
    expect(find.text('Первый банк · 1111'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer sees explanation and cannot import', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, _provider(role: 'viewer'));

    expect(find.text('Только просмотр'), findsOneWidget);
    expect(
      find.textContaining('нет права импортировать банковский снимок'),
      findsOneWidget,
    );
    expect(find.text('Импортировать снимок'), findsNothing);
  });

  testWidgets('successful import reports result and marks missing proof',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var importedForUser = -1;
    await _pump(
      tester,
      _provider(role: 'editor'),
      filePicker: () async =>
          const CashbackImportFile(name: 'snapshot.json', contents: '{}'),
      importer: (provider, contents, userId) async {
        importedForUser = userId;
        return const CashbackImportResult(
          created: 0,
          updated: 2,
          importedBanks: 1,
          skippedBanks: 0,
        );
      },
    );

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(importedForUser, 1);
    expect(find.text('Не найдено в снимке'), findsOneWidget);
    expect(find.textContaining('Снимок импортирован:'), findsOneWidget);
  });

  testWidgets('import error remains visible with recovery action',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _provider(role: 'editor'),
      filePicker: () async =>
          const CashbackImportFile(name: 'broken.json', contents: '{}'),
      importer: (provider, contents, userId) async =>
          throw Exception('снимок требует авторизации'),
    );

    await _tapImport(tester);
    await tester.pumpAndSettle();

    expect(find.text('Снимок не импортирован'), findsOneWidget);
    expect(find.textContaining('снимок требует авторизации'), findsOneWidget);
    expect(find.text('Выбрать файл снова'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  DataProvider provider, {
  CashbackFilePicker? filePicker,
  CashbackDocumentImporter? importer,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: PlanConfirmationScreen(
          filePicker: filePicker,
          documentImporter: importer,
          sessionType: AppSessionType.windows,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapImport(WidgetTester tester) async {
  final button = find.text('Импортировать снимок', skipOffstage: false);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

DataProvider _provider({required String role}) {
  final start = DateTime(2026, 9);
  final provider = DataProvider();
  provider
    ..currentAuthUser = AuthIdentity(id: 8, username: 'test', role: role)
    ..banks = [BankModel(id: 1, name: 'Первый банк', description: '')]
    ..users = [UserModel(id: 1, name: 'Анна')]
    ..cards = [
      CardModel(
        id: 1,
        bankId: 1,
        userId: 1,
        lastFourDigits: '1111',
        paymentSystem: 'МИР',
        cardType: 'debit',
      ),
    ]
    ..cashbackCategories = [
      CashbackCategoryModel(
        id: 1,
        name: 'АЗС',
        startDate: start,
        endDate: DateTime(2026, 10),
        isSelected: true,
        cashbackPercent: 7,
        cardId: 1,
        isBankConfirmed: true,
      ),
      CashbackCategoryModel(
        id: 2,
        name: 'Кафе',
        startDate: start,
        endDate: DateTime(2026, 10),
        isSelected: true,
        cashbackPercent: 5,
        cardId: 1,
      ),
      CashbackCategoryModel(
        id: 3,
        name: 'Бонусное задание',
        startDate: start,
        endDate: DateTime(2026, 10),
        isSelected: true,
        cashbackPercent: 10,
        cardId: 1,
        categoryType: 'task_bonus',
      ),
    ];
  return provider;
}
