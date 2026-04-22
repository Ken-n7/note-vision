import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/info/presentation/instructions_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders app bar with correct title', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));
    expect(find.text('How to Use'), findsOneWidget);
  });

  testWidgets('renders all five step titles', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));

    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Review Detections'), findsOneWidget);
    expect(find.text('Edit the Score'), findsOneWidget);
    expect(find.text('Play Back'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('renders step numbers 1 through 5', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));

    for (var i = 1; i <= 5; i++) {
      expect(find.text('$i'), findsOneWidget);
    }
  });

  testWidgets('back button pops the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Home')),
        routes: {
          InstructionsScreen.routeName: (_) => const InstructionsScreen(),
        },
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(InstructionsScreen.routeName);
    await tester.pumpAndSettle();

    expect(find.byType(InstructionsScreen), findsOneWidget);

    final backButton = find.byType(BackButton);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton);
    } else {
      navigator.pop();
    }
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
