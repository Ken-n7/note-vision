import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_vision/CollectionPage.dart';
import 'package:note_vision/HomePage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: CollectionPage(),
    );
  }

  group('CollectionPage Widget Tests', () {

    testWidgets('Initial UI renders correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('My Files'), findsOneWidget);
      expect(find.text('No Image Found!!'), findsOneWidget);
      expect(find.text('Add Image'), findsOneWidget);
      expect(find.byKey(const ValueKey('addImageButton')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('mainBottomNav')),
          findsOneWidget);
    });

    testWidgets('Drawer opens and shows menu items',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Digital Writing'), findsOneWidget);
      expect(find.text('Instruction'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('Add Image button navigates to HomePage',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.byKey(const ValueKey('addImageButton')));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('BottomNav "Add Files" navigates to HomePage',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Add Files'));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('BottomNav index updates correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      await tester.tap(find.text('Info'));
      await tester.pump();

      final BottomNavigationBar navBar =
          tester.widget(find.byType(BottomNavigationBar));

      expect(navBar.currentIndex, 1);
    });

  });
}