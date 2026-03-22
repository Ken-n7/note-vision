import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';

void main() {
  testWidgets('EmptyCollection shows current copy and handles add tap', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyCollection(
            onAddPressed: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Your collection\nis empty'), findsOneWidget);
    expect(
      find.text(
        'Scan or import a music sheet\nto start building your collection.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add Image'), findsOneWidget);
    expect(find.byKey(const ValueKey('addImageButton')), findsOneWidget);
    expect(find.text('Supports camera scan & file import'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('addImageButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
