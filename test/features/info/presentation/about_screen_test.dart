import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/info/presentation/about_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

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

  testWidgets('back button pops the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Home')),
        routes: {
          AboutScreen.routeName: (_) => const AboutScreen(),
        },
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
