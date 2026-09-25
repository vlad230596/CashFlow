import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/home_screen.dart';
import 'package:cashflow/services/app_session_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('cashback desktop tools are available only in Windows sessions', () {
    for (final sessionType in AppSessionType.values) {
      final shouldSupportDesktopTools = sessionType == AppSessionType.windows;

      expect(
        sessionType.canImportCashbackFile,
        shouldSupportDesktopTools,
        reason: 'file import capability for $sessionType',
      );
      expect(
        sessionType.canLaunchCashbackBrowser,
        shouldSupportDesktopTools,
        reason: 'browser launch capability for $sessionType',
      );
    }
  });

  testWidgets('Android and web sessions hide Windows-only actions',
      (tester) async {
    for (final sessionType in [AppSessionType.android, AppSessionType.web]) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => DataProvider(),
          child: MaterialApp(home: HomeScreen(sessionType: sessionType)),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('shell-destination-Ещё')),
      );
      await tester.pump();

      expect(find.byIcon(Icons.upload_file_outlined), findsNothing);
      expect(find.byIcon(Icons.download_for_offline_outlined), findsNothing);
    }
  });

  testWidgets('Windows session shows its desktop actions', (tester) async {
    final provider = DataProvider()
      ..currentAuthUser = AuthIdentity(
        id: 1,
        username: 'editor',
        role: 'editor',
      );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: HomeScreen(sessionType: AppSessionType.windows),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('shell-destination-Ещё')),
    );
    await tester.pump();

    expect(find.byIcon(Icons.upload_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
  });

  testWidgets('system back restores the previously selected shell tab',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DataProvider(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shell-destination-План')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shell-destination-Ещё')));
    await tester.pump();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
  });

  testWidgets('wide short layout uses the rail without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 270);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DataProvider(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('CashFlow'), findsOneWidget);
    expect(find.text('Выгода'), findsWidgets);
    expect(find.text('План'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
