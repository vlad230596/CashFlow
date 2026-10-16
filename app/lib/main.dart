import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/data_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_log.dart';
import 'theme/cashflow_theme.dart';

void main() async {
  final sinceStart = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.instance = AppLog.persistent(sinceStart: sinceStart);
  AppLog.instance.event('startup: main');
  final binding = WidgetsBinding.instance;
  final dataProvider = DataProvider(
    afterFirstFrame: () => binding.waitUntilFirstFrameRasterized,
  );
  await dataProvider.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (context) => dataProvider,
      child: MyApp(),
    ),
  );
  AppLog.instance.event('startup: runApp');
  unawaited(binding.waitUntilFirstFrameRasterized.then((_) {
    AppLog.instance.event('startup: first frame rasterized '
        'authenticated=${dataProvider.isAuthenticated} '
        'cached=${dataProvider.hasUsableDataSnapshot}');
  }));
  // Only the isolated Android QA APK enables this flag/channel. Report useful
  // cached content after rasterization, rather than timing the splash screen or
  // the automation tool's later accessibility inspection.
  if (const bool.fromEnvironment('CASHFLOW_OFFLINE_QA_METRICS') &&
      dataProvider.isAuthenticated &&
      dataProvider.hasUsableDataSnapshot) {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await const MethodChannel('cashflow/offline_qa')
        .invokeMethod<void>('cachedFrameRasterized');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashFlow',
      debugShowCheckedModeBanner: false,
      theme: CashFlowTheme.light(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataProvider>(
      builder: (context, provider, _) {
        if (!provider.authReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return provider.isAuthenticated
            ? const HomeScreen()
            : const LoginScreen();
      },
    );
  }
}
