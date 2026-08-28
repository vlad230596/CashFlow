import 'package:cash_app/screens/widgets/cashback_description_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the full cashback description on click', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CashbackDescriptionButton(
            categoryName: 'Аптеки',
            description: 'Полные условия категории',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('Аптеки'), findsOneWidget);
    expect(find.text('Полные условия категории'), findsOneWidget);
  });

  testWidgets('does not render an icon for an empty description',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CashbackDescriptionButton(
            categoryName: 'Аптеки',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsNothing);
  });
}
