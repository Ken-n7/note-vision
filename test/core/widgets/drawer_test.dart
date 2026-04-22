import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/features/info/presentation/about_screen.dart';
import 'package:note_vision/features/info/presentation/instructions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _makeApp() {
  return MaterialApp(
    home: const Scaffold(drawer: CollectionDrawer()),
    onGenerateRoute: (settings) {
      if (settings.name == InstructionsScreen.routeName) {
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('InstructionsScreen')),
        );
      }
      if (settings.name == AboutScreen.routeName) {
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('AboutScreen')),
        );
      }
      return null;
    },
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.dragFrom(const Offset(0, 300), const Offset(200, 300));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Digital Writing item does not appear in the drawer',
      (tester) async {
    await tester.pumpWidget(_makeApp());
    await _openDrawer(tester);

    expect(find.text('Digital Writing'), findsNothing);
  });

  testWidgets('Instruction item is present in the drawer', (tester) async {
    await tester.pumpWidget(_makeApp());
    await _openDrawer(tester);

    expect(find.text('Instruction'), findsOneWidget);
  });

  testWidgets('About item is present in the drawer', (tester) async {
    await tester.pumpWidget(_makeApp());
    await _openDrawer(tester);

    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('tapping Instruction navigates to InstructionsScreen',
      (tester) async {
    await tester.pumpWidget(_makeApp());
    await _openDrawer(tester);

    await tester.tap(find.text('Instruction'));
    await tester.pumpAndSettle();

    expect(find.text('InstructionsScreen'), findsOneWidget);
  });

  testWidgets('tapping About navigates to AboutScreen', (tester) async {
    await tester.pumpWidget(_makeApp());
    await _openDrawer(tester);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('AboutScreen'), findsOneWidget);
  });
}
