import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/collection/presentation/widgets/empty_collection.dart';

void main() {
  testWidgets('EmptyCollection shows creation choices and handles taps', (
    WidgetTester tester,
  ) async {
    var scanTapped = false;
    var importTapped = false;
    var newScoreTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyCollection(
            onAddPressed: () {
              scanTapped = true;
            },
            onImportPressed: () {
              importTapped = true;
            },
            onNewScorePressed: () {
              newScoreTapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Your collection\nis empty'), findsOneWidget);
    expect(
      find.text('Scan, import, or start with a blank score.'),
      findsOneWidget,
    );
    expect(find.text('Scan Image'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('New Score'), findsOneWidget);
    expect(find.byKey(const ValueKey('scanImageButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('importMusicXmlButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('newScoreButton')), findsOneWidget);
    expect(
      find.text('Scans work best on handwritten music, flat and well lit'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('scanImageButton')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('importMusicXmlButton')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('newScoreButton')));
    await tester.pump();

    expect(scanTapped, isTrue);
    expect(importTapped, isTrue);
    expect(newScoreTapped, isTrue);
  });
}
