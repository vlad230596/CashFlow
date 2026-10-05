import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/settings/bank_edit_screen.dart';
import 'package:cashflow/utils/identity_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pumpBadges(WidgetTester tester, List<Widget> badges) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Wrap(spacing: 4, runSpacing: 4, children: badges),
      ),
    ),
  );
  // SVG assets are read and parsed asynchronously.
  await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 300),
      ));
  await tester.pumpAndSettle();
}

void main() {
  test('every bank except the neutral one has a bundled logo', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final option in bankIconOptions) {
      if (option.key == 'generic') {
        expect(option.logoAsset, isNull);
        expect(option.icon, isNotNull);
        continue;
      }
      expect(option.logoAsset, 'assets/banks/${option.key}.svg');
      final svg = await rootBundle.loadString(option.logoAsset!);
      expect(svg, contains('<svg'), reason: option.key);
      expect(svg, isNot(contains('<image')), reason: option.key);
    }
  });

  test('bank names map to their logo keys', () {
    expect(defaultBankIconKey('Т-Банк'), 'tbank');
    expect(defaultBankIconKey('Тинькофф'), 'tbank');
    expect(defaultBankIconKey('Альфа-Банк'), 'alfa');
    expect(defaultBankIconKey('Банк ВТБ'), 'vtb');
    expect(defaultBankIconKey('СберБанк'), 'sber');
    expect(defaultBankIconKey('Яндекс Пэй'), 'yandex');
    expect(defaultBankIconKey('Ozon Банк'), 'ozon');
    expect(defaultBankIconKey('Почта Банк'), 'generic');
    expect(bankIconOption(null, bankName: 'ВТБ').logoAsset,
        'assets/banks/vtb.svg');
  });

  testWidgets('badges draw the logo at every size the app uses',
      (tester) async {
    final badges = [
      for (final size in const [16.0, 18.0, 22.0, 24.0, 28.0, 32.0])
        for (final option in bankIconOptions)
          BankIconBadge(
            iconKey: option.key,
            bankName: option.label,
            size: size,
          ),
    ];
    await _pumpBadges(tester, badges);

    expect(tester.takeException(), isNull);
    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    expect(pictures, hasLength(6 * (bankIconOptions.length - 1)));
    for (final size in const [16.0, 24.0, 32.0]) {
      final badge = find.byWidgetPredicate(
        (widget) =>
            widget is BankIconBadge &&
            widget.iconKey == 'tbank' &&
            widget.size == size,
      );
      expect(tester.getSize(badge), Size.square(size));
      expect(
        find.descendant(of: badge, matching: find.byType(ClipRRect)),
        findsOneWidget,
      );
    }
    // Every logo has finished loading: no placeholder is left, and the
    // letter marks are gone.
    expect(
      find.descendant(
        of: find.byType(SvgPicture),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    expect(find.text('ВТБ'), findsNothing);
    expect(find.text('Т'), findsNothing);
    // The neutral bank keeps its icon.
    expect(find.byIcon(Icons.account_balance_rounded), findsNWidgets(6));
  });

  testWidgets('badges keep their semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBadges(tester, const [
      BankIconBadge(iconKey: 'sber', bankName: 'СберБанк', size: 24),
    ]);
    expect(find.bySemanticsLabel('Иконка банка СберБанк'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the bank icon picker shows the logos and switches them',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DataProvider(),
        child: MaterialApp(
          home: BankEditScreen(
            existingBank: BankModel(id: 3, name: 'ВТБ', iconKey: 'vtb'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 300),
        ));
    await tester.pumpAndSettle();

    ChoiceChip chip(String key) =>
        tester.widget<ChoiceChip>(find.byKey(ValueKey('bank-icon-$key')));
    for (final option in bankIconOptions) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('bank-icon-${option.key}')),
          matching: find.byType(SvgPicture),
        ),
        option.logoAsset == null ? findsNothing : findsOneWidget,
        reason: option.key,
      );
    }
    expect(chip('vtb').selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('bank-icon-sber')));
    await tester.pump();
    expect(chip('sber').selected, isTrue);
    expect(chip('vtb').selected, isFalse);
  });

  testWidgets('a missing logo falls back to the letter mark', (tester) async {
    const option = BankIconOption(
      key: 'missing',
      label: 'Тест',
      background: Color(0xFF0A6EC7),
      foreground: Colors.white,
      mark: 'ВТБ',
      logoAsset: 'assets/banks/does-not-exist.svg',
    );
    await _pumpBadges(tester, const [BankIconMark(option: option, size: 24)]);
    expect(find.text('ВТБ'), findsOneWidget);
  });
}
