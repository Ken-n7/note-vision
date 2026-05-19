import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/scan/presentation/widgets/scan_actions.dart';

void main() {
  testWidgets('renders stacked landscape actions without parent-data errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanActions(onRedo: () {}, onImport: () {}, onContinue: () {}),
        ),
      ),
    );

    expect(find.text('Redo'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
