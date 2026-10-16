import 'package:cashflow/screens/widgets/keyboard_first_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('arrow hides keyboard, preserves route and text, then navigates',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar:
                              AppBar(leading: const KeyboardFirstBackButton()),
                          body: TextField(controller: controller),
                        ),
                      )),
                  child: const Text('Open editor'),
                ),
              )),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'keep this draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(controller.text, 'keep this draft');
    expect(tester.testTextInput.isVisible, isFalse);

    tester.view.resetViewInsets();
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('arrow without keyboard respects a route PopScope',
      (tester) async {
    var attempted = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PopScope(
                        canPop: false,
                        onPopInvokedWithResult: (didPop, _) =>
                            attempted = !didPop,
                        child: Scaffold(
                          appBar:
                              AppBar(leading: const KeyboardFirstBackButton()),
                          body: const Text('Guarded editor'),
                        ),
                      ),
                    )),
                child: const Text('Open'),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(attempted, isTrue);
    expect(find.text('Guarded editor'), findsOneWidget);
  });
}
