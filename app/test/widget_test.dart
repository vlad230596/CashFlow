import 'package:cashflow/main.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CashFlow app starts', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DataProvider(),
        child: const MyApp(),
      ),
    );

    expect(find.text('CashFlow'), findsOneWidget);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}
