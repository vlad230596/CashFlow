import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/more_screen.dart';
import 'package:cashflow/services/app_session_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('viewer sees compact essentials without administrative tools',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider(role: 'viewer');

    await tester.pumpWidget(_app(provider));

    expect(find.text('Ещё'), findsOneWidget);
    expect(find.text('Данные обновлены'), findsOneWidget);
    expect(find.text('ПАРАМЕТРЫ'), findsOneWidget);
    expect(find.text('АККАУНТ И ПРИЛОЖЕНИЕ'), findsOneWidget);
    expect(find.text('anna · Просмотр'), findsOneWidget);
    expect(find.text('Управление данными'), findsNothing);
    expect(find.text('Импортировать JSON'), findsNothing);
    expect(find.text('Запросить кешбэк'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin sees management and Windows tools at expanded width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider(role: 'admin')
      ..users = [UserModel(id: 1, name: 'Анна'), UserModel(id: 2, name: 'Иван')]
      ..banks = [BankModel(id: 1, name: 'Банк', description: '')]
      ..cards = [CardModel(id: 1), CardModel(id: 2), CardModel(id: 3)];

    await tester.pumpWidget(
      _app(provider, sessionType: AppSessionType.windows),
    );

    expect(find.text('Управление данными'), findsOneWidget);
    expect(find.text('Владельцы карт'), findsOneWidget);
    expect(find.text('Импортировать JSON'), findsOneWidget);
    expect(find.text('Запросить кешбэк'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('anna · Администратор'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh explains cached state and supports retry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider(role: 'editor')
      ..nextRefreshResult = false;

    await tester.pumpWidget(_app(provider));
    await tester.tap(find.byKey(const ValueKey('refreshButton')));
    await tester.pumpAndSettle();

    expect(provider.refreshCalls, 1);
    expect(find.text('Не удалось обновить'), findsOneWidget);
    expect(find.text('Показываем сохранённые данные'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('historical date can be reset and logout is delegated',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider(role: 'viewer');
    await provider.setCashbackEffectiveDate(DateTime(2025, 2, 10));

    await tester.pumpWidget(_app(provider));
    expect(find.text('Исторический режим'), findsOneWidget);
    expect(find.text('10.02.2025'), findsOneWidget);

    await tester.tap(find.text('Использовать сегодня'));
    await tester.pumpAndSettle();
    expect(provider.usesCurrentCashbackDate, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('logoutButton')));
    await tester.tap(find.byKey(const ValueKey('logoutButton')));
    await tester.pump();
    expect(provider.loggedOut, isTrue);
  });

  testWidgets('compact layout tolerates large text in dark mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _TestDataProvider(role: 'admin');

    await tester.pumpWidget(
      _app(
        provider,
        theme: ThemeData.dark(useMaterial3: true),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(find.text('Расчётная дата кешбэка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  DataProvider provider, {
  AppSessionType sessionType = AppSessionType.android,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      theme: theme ?? ThemeData(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: MoreScreen(
            sessionType: sessionType,
            now: _fixedNow,
          ),
        ),
      ),
    ),
  );
}

DateTime _fixedNow() => DateTime(2026, 9, 22, 10);

class _TestDataProvider extends DataProvider {
  _TestDataProvider({required String role})
      : super(apiBaseUrl: 'https://cashflow.test') {
    currentAuthUser = AuthIdentity(id: 1, username: 'anna', role: role);
    lastUpdated = '2026-09-22T09:38:00';
  }

  bool nextRefreshResult = true;
  int refreshCalls = 0;
  bool loggedOut = false;

  @override
  Future<bool> fetchAllData() async {
    refreshCalls += 1;
    if (nextRefreshResult) {
      lastUpdated = '2026-09-22T10:00:00';
      notifyListeners();
    }
    return nextRefreshResult;
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }
}
