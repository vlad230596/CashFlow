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

      expect(find.byIcon(Icons.upload_file_outlined), findsNothing);
      expect(find.byIcon(Icons.download_for_offline_outlined), findsNothing);
    }
  });

  testWidgets('Windows session shows its desktop actions', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DataProvider(),
        child: const MaterialApp(
          home: HomeScreen(sessionType: AppSessionType.windows),
        ),
      ),
    );

    expect(find.byIcon(Icons.upload_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
  });
}
