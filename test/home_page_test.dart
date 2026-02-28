import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/HomePage.dart'; // Adjust import to your actual path
// 👆 replace with your actual package import

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: HomePage(),
    );
  }

  group('HomePage Widget Tests', () {

    testWidgets('Initial UI renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Note Vision'), findsOneWidget);
      expect(find.text('Capture Music Sheet'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsWidgets);
      expect(find.text('Scan Sheet'), findsOneWidget);
      expect(find.text('Upload Image'), findsOneWidget);
    });

    testWidgets('Drawer opens when menu button is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
    });

    testWidgets('Bottom navigation switches to Result tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Result'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Recognition / Result'), findsOneWidget);
    });

    testWidgets('Bottom navigation switches to Files tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your saved scans'), findsOneWidget);
    });

    testWidgets('Tapping Scan Sheet button triggers action',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Scan Sheet'));
      await tester.pump();

      // We cannot test actual camera launch,
      // but we verify button is tappable without crashing.
      expect(find.text('Scan Sheet'), findsOneWidget);
    });

    testWidgets('Bottom navigation Scan tab triggers camera flow safely',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Scan'));
      await tester.pump();

      // Should not crash
      expect(find.text('Note Vision'), findsOneWidget);
    });
  });
}