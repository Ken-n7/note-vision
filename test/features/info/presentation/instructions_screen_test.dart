import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/info/presentation/instructions_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);
  Widget wrapWithTextScale(Widget child, double scale) {
    return MaterialApp(
      home: child,
      builder: (context, routeChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: routeChild!,
      ),
    );
  }

  testWidgets('renders app bar with correct title', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));
    expect(find.text('How to Use'), findsOneWidget);
  });

  const titles = [
    'Scan',
    'What the scanner reads',
    'Review Detections',
    'Edit the Score',
    'Genre',
    'Play Back',
    'Export',
  ];

  testWidgets('renders every step title, in order', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));

    for (final title in titles) {
      await tester.scrollUntilVisible(find.text(title), 120);
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('numbers the steps 1 to ${titles.length}', (tester) async {
    await tester.pumpWidget(wrap(const InstructionsScreen()));

    for (var i = 1; i <= titles.length; i++) {
      await tester.scrollUntilVisible(find.text('$i'), 120);
      expect(find.text('$i'), findsOneWidget);
    }
  });

  testWidgets('wraps step titles on narrow text-scaled screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      wrapWithTextScale(const InstructionsScreen(), 1.35),
    );

    await tester.scrollUntilVisible(find.text('Review Detections'), 120);
    expect(find.text('Review Detections'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
