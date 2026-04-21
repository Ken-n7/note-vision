import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/main.dart';
import 'package:note_vision/features/landing/presentation/landing_screen.dart';

void main() {
  testWidgets('App builds and shows LandingScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LandingScreen), findsOneWidget);
  });

  testWidgets('Debug banner is disabled', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.debugShowCheckedModeBanner, false);
  });
}
