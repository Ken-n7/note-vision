import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/landing/presentation/landing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget makeTestableWidget(Widget child) {
    return MaterialApp(home: child);
  }

  testWidgets('LandingScreen displays title, logo, tagline, and actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(makeTestableWidget(const LandingScreen()));
    await tester.pump();

    expect(find.text('Note Vision'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Read music. Understand it.'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text("Dev's Workbench"), findsOneWidget);
  });

  testWidgets('Pressing Get Started navigates to CollectionScreen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});

    await tester.pumpWidget(makeTestableWidget(const LandingScreen()));
    await tester.pump();

    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(CollectionScreen), findsOneWidget);
  });
}
