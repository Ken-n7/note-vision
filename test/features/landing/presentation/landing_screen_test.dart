import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/landing/presentation/landing_screen.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';

void main() {

  Widget makeTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  testWidgets('LandingScreen displays title, logo and button',
      (WidgetTester tester) async {

    await tester.pumpWidget(
      makeTestableWidget(const LandingScreen()),
    );

    expect(find.text('Note Vision'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('getStartedButton')), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('Pressing Get Started navigates to CollectionScreen',
      (WidgetTester tester) async {

    await tester.pumpWidget(
      makeTestableWidget(const LandingScreen()),
    );

    await tester.tap(find.byKey(const Key('getStartedButton')));
    await tester.pumpAndSettle();

    expect(find.byType(CollectionScreen), findsOneWidget);
  });
}