import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cashflow/screens/settings/emoji_picker_screen.dart';
import 'package:cashflow/theme/cashflow_theme.dart';
import 'package:cashflow/utils/emoji_catalog.dart';
import 'package:cashflow/utils/identity_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleAssets(WidgetTester tester) async {
  await tester.pump();
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  test('complete catalogue has bundled graphics and matches the API allowlist',
      () async {
    final entries = await EmojiCatalog.load();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();
    final backendKeys = (jsonDecode(
      File('../backend/data/user_emoji_keys.json').readAsStringSync(),
    ) as List)
        .cast<String>()
        .toSet();
    expect(entries.length, 3953);
    expect(entries.map((entry) => entry.iconKey).toSet(), backendKeys);
    for (final entry in entries) {
      expect(assets, contains(entry.assetPath), reason: entry.label);
      expect(userEmojiAsset(entry.iconKey), entry.assetPath,
          reason: entry.label);
    }
    for (final key in ['boy', 'girl', 'person', 'family', null]) {
      expect(assets, contains(userEmojiAsset(key)));
    }
    expect(entries.where((entry) => entry.matches('ЛИСА')).map((e) => e.emoji),
        contains('🦊'));
    expect(entries.where((entry) => entry.matches('fox')).map((e) => e.emoji),
        contains('🦊'));
    expect(entries.where((entry) => entry.matches('🦊')).map((e) => e.emoji),
        contains('🦊'));
    expect(normalizeEmojiSearch(' ЁЖ '), 'еж');
    expect(emojiGroupLabels[entries.singleWhere((e) => e.emoji == '🦊').group],
        'Животные и природа');
    expect(
        emojiGroupLabels[entries.singleWhere((e) => e.emoji == '🇷🇺').group],
        'Флаги');
  });

  testWidgets('search, empty results, clearing and selection work',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EmojiPickerScreen(
                              selectedIconKey: 'emoji:🙂'),
                        ));
                  },
                  child: const Text('Выбрать'),
                ),
              )),
    ));
    await tester.tap(find.text('Выбрать'));
    await settleAssets(tester);
    expect(find.text('Найдено: 3953'), findsOneWidget);
    // The complete collection stays lazy even on a large viewport.
    expect(find.byType(UserIconBadge).evaluate().length, lessThan(200));
    await tester.enterText(
        find.byKey(const ValueKey('emoji-search')), 'несуществующийэмодзи');
    await tester.pumpAndSettle();
    expect(find.text('Эмодзи не найдены'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await settleAssets(tester);
    expect(find.text('Найдено: 3953'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('emoji-search')), 'лиса');
    await settleAssets(tester);
    await tester.tap(find.byKey(const ValueKey('emoji:🦊')));
    await tester.pumpAndSettle();
    expect(selected, 'emoji:🦊');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'picker fits narrow, landscape and desktop widths with large text',
      (tester) async {
    final boundary = GlobalKey();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(1100, 800)
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(
        theme: CashFlowTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: boundary,
          child: const EmojiPickerScreen(selectedIconKey: 'emoji:🦊'),
        ),
      ));
      await settleAssets(tester);
      expect(tester.takeException(), isNull, reason: '$size');
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
      theme: CashFlowTheme.light(),
      home: RepaintBoundary(
        key: boundary,
        child: const EmojiPickerScreen(selectedIconKey: 'emoji:🦊'),
      ),
    ));
    await settleAssets(tester);
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/emoji-picker-preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
