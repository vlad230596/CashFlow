import 'package:cashflow/utils/cashback_period.dart';
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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/mcc_test_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('compact overview shows both stages without a reproach',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _provider(role: 'editor');
    await _pump(tester, provider);

    expect(find.text('Два шага: выбрать и проверить'), findsOneWidget);
    expect(find.text('1 из 2'), findsOneWidget);
    expect(find.text('Первый банк · 1111'), findsOneWidget);
    expect(find.text('Подтверждено частично'), findsOneWidget);
    expect(find.text('Есть расхождение'), findsNothing);
    expect(find.text('Подтверждение'), findsOneWidget);
    expect(find.text('Выгода'), findsOneWidget);

    await tester.tap(find.text('Первый банк · 1111'));
    await tester.pumpAndSettle();

    expect(find.text('Выбор по карте'), findsOneWidget);
    expect(find.text('Шаг 1. Выбрать категории в банке'), findsOneWidget);
    expect(find.text('Шаг 2. Проверить выбор'), findsOneWidget);
    expect(find.text('Открыть браузер с планом'), findsOneWidget);
    expect(find.text('Проверить выбор', skipOffstage: false), findsOneWidget);
    expect(find.text('Ждёт проверки', skipOffstage: false), findsOneWidget);
    expect(
        provider.cashbackCategories.every((item) => item.isSelected), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact completed card opens confirmation details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
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

    expect(find.text('Подтверждено'), findsOneWidget);
    expect(find.text('Два шага: выбрать и проверить'), findsNothing);
    expect(
      find.text('Подтверждено банком', skipOffstage: false),
      findsNWidgets(2),
    );
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
    expect(find.text('Ждёт подтверждения'), findsOneWidget);
    expect(find.text('Проверить выбор', skipOffstage: false), findsOneWidget);
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
    expect(find.text('АЗС', skipOffstage: false), findsOneWidget);

    tester.view.physicalSize = const Size(1100, 900);
    await tester.pumpAndSettle();

    expect(find.text('Первый банк · 1111'), findsNWidgets(2));
    expect(find.text('АЗС', skipOffstage: false), findsOneWidget);
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

    expect(find.text('Два шага: выбрать и проверить'), findsOneWidget);
    final card = find.text('Первый банк · 1111');
    await tester.scrollUntilVisible(card, 200);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer sees explanation and cannot check', (tester) async {
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
    expect(find.text('Проверить выбор', skipOffstage: false), findsNothing);
  });

  testWidgets('stage 1 opens the owner profile with the plan checklist',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    CashbackImportProfile? launched;
    String? plan;
    await _pump(
      tester,
      _provider(role: 'editor'),
      launcher: (profile, {selectionPlan}) async {
        launched = profile;
        plan = selectionPlan;
        return null;
      },
    );

    final open = find.byKey(const ValueKey('confirmation-open-browser'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(launched?.id, 'user-1');
    expect(plan, isNotNull);
    expect(find.textContaining('Профиль 1 (с ВТБ) открыт'), findsOneWidget);
  });

  testWidgets(
      'check imports for the card owner and accepts a bank choice '
      'outside the plan', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _provider(role: 'editor');
    var importedForUser = -1;
    await _pump(
      tester,
      provider,
      filePicker: () async =>
          const CashbackImportFile(name: 'snapshot.json', contents: '{}'),
      importer: (provider, contents, userId) async {
        importedForUser = userId;
        // What the server does: the bank chose «Такси» on the spot (added to
        // the plan, confirmed); «Кафе» stays planned without confirmation.
        provider.cashbackCategories = [
          ...provider.cashbackCategories,
          CashbackCategoryModel(
            id: 4,
            name: 'Такси',
            startDate: DateTime(2026, 9),
            endDate: DateTime(2026, 10),
            isSelected: true,
            isBankConfirmed: true,
            cashbackPercent: 3,
            cardId: 1,
          ),
        ];
        provider.notifyCashbackCategoriesChanged();
        return const CashbackImportResult(
          created: 1,
          updated: 2,
          importedBanks: 1,
          skippedBanks: 0,
        );
      },
    );

    await _tapCheck(tester);
    await tester.pumpAndSettle();

    expect(importedForUser, 1);
    expect(
      find.textContaining('Анна: импортировано банков: 1'),
      findsOneWidget,
    );
    expect(find.text('Результат проверки'), findsOneWidget);
    expect(find.text('Выбрано в банке', skipOffstage: false), findsOneWidget);
    expect(find.text('Из банка', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Банк не подтвердил', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Есть расхождение', skipOffstage: false), findsNothing);
    expect(find.text('Не найдено в снимке', skipOffstage: false), findsNothing);
    expect(
      find.text('Проверить ещё раз', skipOffstage: false),
      findsOneWidget,
    );

    // Let the import snackbar go: it covers the bottom of the details.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final adopt = find.byKey(const ValueKey('confirmation-adopt-bank'));
    await tester.scrollUntilVisible(
      adopt,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('confirmation-details-1')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(adopt);
    await tester.pumpAndSettle();

    expect(
      provider.cashbackCategories.firstWhere((item) => item.id == 2).isSelected,
      isFalse,
    );
    expect(find.text('Кафе', skipOffstage: false), findsNothing);
    expect(find.text('2 из 2', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import error remains visible with recovery action',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
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

    await _tapCheck(tester);
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
  CashbackBrowserLauncher? launcher,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: PlanConfirmationScreen(
          period: CashbackPeriod.month(DateTime(2026, 9)),
          filePicker: filePicker,
          documentImporter: importer,
          browserLauncher: launcher,
          sessionType: AppSessionType.windows,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapCheck(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('confirmation-check'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

DataProvider _provider({required String role}) {
  final start = DateTime(2026, 9);
  final provider = DataProvider(
    mccCacheStore: isolatedMccCache(),
    apiBaseUrl: 'https://cashflow.test',
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );
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
