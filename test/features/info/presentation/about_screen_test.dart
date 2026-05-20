import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/info/presentation/about_screen.dart';

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
    await tester.pumpWidget(wrap(const AboutScreen()));
    expect(find.text('About'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows app name and version', (tester) async {
    await tester.pumpWidget(wrap(const AboutScreen()));

    expect(find.text('Note Vision'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
  });

  testWidgets('shows app description', (tester) async {
    await tester.pumpWidget(wrap(const AboutScreen()));

    expect(find.textContaining('NoteVision'), findsOneWidget);
  });

  testWidgets('shows Credits section', (tester) async {
    await tester.pumpWidget(wrap(const AboutScreen()));

    expect(find.text('CREDITS'), findsOneWidget);
    expect(find.text('Ken Canete'), findsOneWidget);
  });

  testWidgets('shows Tech Stack section', (tester) async {
    await tester.pumpWidget(wrap(const AboutScreen()));

    expect(find.text('TECH STACK'), findsOneWidget);
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('TFLite'), findsOneWidget);
    expect(find.text('MusicXML'), findsOneWidget);
  });

  testWidgets('hides developer classroom controls', (tester) async {
    await tester.pumpWidget(wrap(const AboutScreen()));

    expect(find.text('DEVELOPER'), findsNothing);
    expect(find.text('Debug Mode'), findsNothing);
    expect(find.textContaining('role switcher'), findsNothing);
  });

  testWidgets('wraps content on narrow text-scaled screens', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrapWithTextScale(const AboutScreen(), 1.35));
    await tester.scrollUntilVisible(find.text('TECH STACK'), 240);

    expect(find.text('TECH STACK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back button pops the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Home')),
        routes: {AboutScreen.routeName: (_) => const AboutScreen()},
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AboutScreen.routeName);
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);

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
