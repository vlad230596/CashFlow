import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/data_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dataProvider = DataProvider();
  await dataProvider.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (context) => dataProvider,
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashFlow',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'RobotoLocal',
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
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
