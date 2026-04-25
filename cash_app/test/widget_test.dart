import 'package:cash_app/main.dart';
import 'package:cash_app/providers/data_provider.dart';
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
    expect(find.text('Cashback'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('MonthCashback'), findsOneWidget);
  });
}
