import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/collection/presentation/collection_screen.dart';
import 'package:note_vision/features/landing/presentation/landing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget makeTestableWidget(Widget child) {
    return MaterialApp(home: child);
  }

  testWidgets('LandingScreen displays title, logo, and tagline', (
    WidgetTester tester,
  ) async {
    // first_launch_done not set → shows splash animation (2200ms hold)
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});

    await tester.pumpWidget(makeTestableWidget(const LandingScreen()));
    await tester.pump(); // SharedPreferences loads; 2200ms timer starts

    // FadeTransition keeps widgets in tree even at opacity 0
    expect(find.text('Note Vision'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Read music. Understand it.'), findsOneWidget);
    // No buttons — navigation is fully automatic
    expect(find.text('Get Started'), findsNothing);

    // Drain the 2200ms hold timer to avoid "pending timer" test assertion
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump(); // isOnboardingComplete() completes
    await tester.pump(const Duration(milliseconds: 450)); // fade transition
  });

  testWidgets('auto-navigates to CollectionScreen on subsequent launch', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'first_launch_done': true,
      'onboarding_complete': true,
    });

    await tester.pumpWidget(makeTestableWidget(const LandingScreen()));
    await tester.pump(); // SharedPreferences.getInstance() completes
    await tester.pump(); // isOnboardingComplete() completes
    await tester.pump(const Duration(milliseconds: 450)); // fade transition

    expect(find.byType(CollectionScreen), findsOneWidget);
  });
}
