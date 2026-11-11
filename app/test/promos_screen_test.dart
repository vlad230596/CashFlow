import 'package:cashflow/models/promo_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/home_screen.dart';
import 'package:cashflow/screens/more_screen.dart';
import 'package:cashflow/screens/promos_screen.dart';
import 'package:cashflow/services/app_session_type.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/reminder_notification_service.dart';
import 'package:cashflow/theme/cashflow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('list sorts by expiry, emphasizes urgent items and filters',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPromos();

    await tester.pumpWidget(_app(provider, const PromosScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Истекает сегодня'), findsOneWidget);
    expect(find.text('Сгорит через 3 дн.'), findsOneWidget);
    expect(find.text('Сгорит через 20 дн.'), findsOneWidget);
    expect(find.text('Срок не указан'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-urgent-banner')), findsOneWidget);
    expect(find.text('Скоро сгорят: 2 — осталось 3 дн. или меньше'),
        findsOneWidget);
    final order = [
      'Пятёрочка: 300 баллов',
      'Самокат: скидка 300 ₽',
      'Ozon: скидка 500 ₽',
      'Без срока',
    ].map((title) => tester.getTopLeft(find.text(title)).dy).toList();
    expect(order, orderedEquals([...order]..sort()));
    expect(find.text('Пятёрочка · 1 250 баллов'), findsOneWidget);
    expect(find.text('Истёк 10.11.2026'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('promo-filter-expired')));
    await tester.pumpAndSettle();
    expect(find.text('Истёк 10.11.2026'), findsOneWidget);
    expect(find.text('Истекает сегодня'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('promo-filter-used')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promo-filter-used')));
    await tester.pumpAndSettle();
    expect(find.text('Использованный'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy button puts the promo code on the clipboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final provider = _providerWithPromos();

    await tester.pumpWidget(_app(provider, const PromosScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promo-copy-id:1')));
    await tester.pump();

    expect(copied, ['SAM300']);
    expect(find.text('Промокод SAM300 скопирован'), findsOneWidget);
  });

  testWidgets('details show code, verbatim source and status actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPromos();

    await tester.pumpWidget(
      _app(provider, const PromoDetailsScreen(promoKey: 'id:1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('SAM300'), findsOneWidget);
    expect(find.text('Сгорит через 3 дн.'), findsOneWidget);
    expect(find.text('За 3 дн., За 1 день'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-mark-used')), findsOneWidget);
    await tester.tap(find.text('Исходное сообщение'));
    await tester.pumpAndSettle();
    expect(find.text(_samokatSource), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('promo-mark-used')));
    await tester.pumpAndSettle();
    expect(provider.usedCalls, [1]);
    expect(find.byKey(const ValueKey('promo-unuse')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paste-and-parse pre-fills the editor and saves the source',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider();

    await tester.pumpWidget(_app(provider, const PromoEditScreen()));
    await tester.pumpAndSettle();

    final chip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('reminder-day-3')),
    );
    expect(chip.selected, isTrue);
    expect(find.text('В последний день'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-no-expiry-hint')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('promo-source-text')),
      _samokatSource,
    );
    await tester.tap(find.byKey(const ValueKey('promo-parse')));
    await tester.pumpAndSettle();

    expect(provider.parsedTexts, [_samokatSource]);
    expect(find.byKey(const ValueKey('promo-parse-summary')), findsOneWidget);
    expect(find.textContaining('Найдено: срок, промокод, магазин, выгода'),
        findsOneWidget);
    expect(find.textContaining('(«до 14 ноября»)'), findsOneWidget);
    expect(find.text('SAM300'), findsOneWidget);
    expect(find.text('Самокат: скидка 300 ₽'), findsOneWidget);
    expect(find.text('14.11.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-no-expiry-hint')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('promo-save')));
    await tester.pumpAndSettle();

    final saved = provider.created.single;
    expect(saved.kind, PromoKind.promo);
    expect(saved.title, 'Самокат: скидка 300 ₽');
    expect(saved.merchant, 'Самокат');
    expect(saved.promoCode, 'SAM300');
    expect(saved.discount, 'скидка 300 ₽');
    expect(saved.expiresAt, DateTime(2026, 11, 14));
    expect(saved.sourceText, _samokatSource);
    expect(saved.reminderDays, [3, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared text pre-fills and parses the editor on open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider();

    await tester.pumpWidget(_app(
      provider,
      const PromoEditScreen(initialText: _samokatSource),
    ));
    await tester.pumpAndSettle();

    expect(provider.parsedTexts, [_samokatSource]);
    expect(find.text('SAM300'), findsOneWidget);
  });

  testWidgets('More lists the section with the active count and opens it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPromos();

    await tester.pumpWidget(_app(
      provider,
      const Scaffold(body: MoreScreen(sessionType: AppSessionType.android)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Промокоды и баллы'), findsOneWidget);
    expect(find.text('Скоро сгорят: 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-promos')));
    await tester.pumpAndSettle();
    expect(find.byType(PromosScreen), findsOneWidget);
  });

  testWidgets('a promo reminder tap opens the item over More', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPromos();

    await tester.pumpWidget(_app(provider, const HomeScreen()));
    await tester.pump();
    provider.simulateReminderTap(const ReminderTarget(ReminderKind.promo, 3));
    // The Benefit tab keeps a progress animation; pump frames explicitly.
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The list route stays underneath the details route.
    expect(find.byType(PromosScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(PromoDetailsScreen), findsOneWidget);
    expect(find.text('Ozon: скидка 500 ₽'), findsOneWidget);
    expect(provider.pendingReminderTarget, isNull);
  });
}

const _samokatSource =
    'Самокат: промокод SAM300 на скидку 300 ₽ до 14 ноября.\nНе суммируется.';

Widget _app(DataProvider provider, Widget home) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(theme: CashFlowTheme.light(), home: home),
    );

_TestDataProvider _providerWithPromos() {
  final provider = _TestDataProvider();
  final today = provider.businessToday;
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);
  provider.promos = [
    PromoModel(
      id: 1,
      kind: PromoKind.promo,
      title: 'Самокат: скидка 300 ₽',
      merchant: 'Самокат',
      promoCode: 'SAM300',
      discount: 'скидка 300 ₽',
      sourceText: _samokatSource,
      expiresAt: day(3),
    ),
    PromoModel(
      id: 2,
      kind: PromoKind.points,
      title: 'Пятёрочка: 300 баллов',
      merchant: 'Пятёрочка',
      pointsAmount: 1250,
      pointsUnit: 'баллов',
      expiresAt: day(0),
    ),
    PromoModel(
      id: 3,
      kind: PromoKind.promo,
      title: 'Ozon: скидка 500 ₽',
      expiresAt: day(20),
    ),
    const PromoModel(id: 4, kind: PromoKind.promo, title: 'Без срока'),
    PromoModel(
      id: 5,
      kind: PromoKind.promo,
      title: 'Истёкший',
      expiresAt: day(-1),
    ),
    PromoModel(
      id: 6,
      kind: PromoKind.promo,
      title: 'Использованный',
      expiresAt: day(5),
      isUsed: true,
      usedAt: DateTime.utc(2026, 11, 1),
    ),
  ];
  return provider;
}

class _TestDataProvider extends DataProvider {
  _TestDataProvider()
      : super(
          mccCacheStore: isolatedMccCache(),
          reminderNotificationService: FakeReminders(),
          businessClock: BusinessClock(now: () => DateTime.utc(2026, 11, 11, 9)),
        );

  final parsedTexts = <String>[];
  final created = <PromoModel>[];
  final usedCalls = <int>[];

  void simulateReminderTap(ReminderTarget target) {
    pendingReminderTarget = target;
    notifyListeners();
  }

  @override
  Future<PromoParseResult> parsePromoText(String text) async {
    parsedTexts.add(text);
    return PromoParseResult(
      title: 'Самокат: скидка 300 ₽',
      merchant: 'Самокат',
      promoCode: 'SAM300',
      discount: 'скидка 300 ₽',
      description: 'Не суммируется.',
      expiresAt: DateTime(2026, 11, 14),
      expiryPhrase: 'до 14 ноября',
    );
  }

  @override
  Future<PromoModel> createPromo(PromoModel item) async {
    created.add(item);
    return item;
  }

  @override
  Future<PromoModel> fetchPromo(int id) async =>
      promos.firstWhere((item) => item.id == id);

  @override
  Future<PromoModel> setPromoUsed(int id, bool used) async {
    usedCalls.add(id);
    final index = promos.indexWhere((item) => item.id == id);
    final current = promos[index];
    final next = PromoModel(
      id: current.id,
      kind: current.kind,
      title: current.title,
      merchant: current.merchant,
      promoCode: current.promoCode,
      discount: current.discount,
      sourceText: current.sourceText,
      expiresAt: current.expiresAt,
      isUsed: used,
      usedAt: used ? DateTime.utc(2026, 11, 11) : null,
    );
    promos = [...promos]..[index] = next;
    notifyListeners();
    return next;
  }
}
