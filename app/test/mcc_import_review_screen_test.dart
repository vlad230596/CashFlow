import 'dart:convert';

import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/mcc_rule_model.dart';
import 'package:cashflow/screens/settings/mcc_import_review_screen.dart';
import 'package:cashflow/services/cashback_import_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bank = BankModel(id: 7, name: 'Тестовый банк');

  Map<String, dynamic> validDocument() => {
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': 7,
        'programKey': 'main',
        'programName': 'Программа лояльности',
        'collectedAt': '2026-09-21T11:29:00Z',
        'source': {'type': 'manual_verified'},
        'validity': {
          'from': '2026-10-01',
          'to': '2026-10-31',
          'confidence': 'confirmed',
        },
        'completeness': 'exact_mcc',
        'globalExcludedMcc': <String>[],
        'conditions': <Object>[],
        'categories': [
          {
            'sourceKey': 'beauty',
            'name': 'Красота',
            'includedMcc': ['7230', '7298'],
            'excludedMcc': <String>[],
            'conditions': <Object>[],
          },
        ],
      };

  MccRuleRevisionModel revision({String status = 'draft'}) =>
      MccRuleRevisionModel(
        id: 129,
        bankId: 7,
        programKey: 'main',
        programName: 'Программа лояльности',
        validFrom: DateTime(2026, 10),
        validTo: DateTime(2026, 10, 31),
        validityConfidence: 'confirmed',
        completeness: 'exact_mcc',
        status: status,
        recordedAt: DateTime(2026, 9, 21),
        sourceType: 'manual_verified',
        globalExcludedMcc: const [],
        conditions: const [],
        categories: const [],
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    CashbackImportFile? file,
    MccSnapshotCreator? creator,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: MccImportReviewScreen(
          bank: bank,
          initialFile: file,
          snapshotCreator: creator,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact mode is intentionally read-only', (tester) async {
    await pumpScreen(
      tester,
      width: 390,
      file: CashbackImportFile(
        name: 'rules.json',
        contents: json.encode(validDocument()),
      ),
    );

    expect(find.textContaining('Режим сводки'), findsOneWidget);
    expect(find.textContaining('Программа лояльности'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Открыть в широком окне'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Открыть в широком окне'), findsOneWidget);
    expect(find.text('Создать черновик'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded mode creates a draft through the existing contract',
      (tester) async {
    Map<String, dynamic>? submitted;
    await pumpScreen(
      tester,
      width: 1280,
      file: CashbackImportFile(
        name: 'rules.json',
        contents: json.encode(validDocument()),
      ),
      creator: (document) async {
        submitted = document;
        return revision();
      },
    );

    expect(find.text('Предварительный просмотр изменений'), findsOneWidget);
    expect(find.text('Красота'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('mcc-import-summary-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать черновик'));
    await tester.pumpAndSettle();

    expect(submitted?['kind'], 'bank_mcc_rules_snapshot');
    expect(find.text('Опубликовать ревизию №129'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid JSON shows a focused blocking error', (tester) async {
    await pumpScreen(
      tester,
      width: 1100,
      file: const CashbackImportFile(
        name: 'broken.json',
        contents: '{not-json',
      ),
    );

    expect(
        find.byKey(const ValueKey('mcc-import-diagnostics')), findsOneWidget);
    expect(find.textContaining('JSON:'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('mcc-import-summary-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать черновик'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Создать черновик'),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text remains scrollable without overflow', (tester) async {
    await pumpScreen(
      tester,
      width: 1000,
      textScale: 2,
      file: CashbackImportFile(
        name: 'rules-with-a-very-long-name.json',
        contents: json.encode(validDocument()),
      ),
    );

    expect(find.text('Сводка ревизии'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
