import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

void main() {
  Future<void> pumpPalette(WidgetTester tester) async {
    tester.view.physicalSize = const Size(240, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: SymbolPalette(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows and hides palette arrows based on scroll position', (
    tester,
  ) async {
    await pumpPalette(tester);

    final leftArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-left-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    final rightArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-right-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );

    expect(leftArrow.opacity, 0);
    expect(rightArrow.opacity, 1);

    await tester.tap(find.byTooltip('Scroll palette right'));
    await tester.pumpAndSettle();

    final midLeftArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-left-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    final midRightArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-right-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );

    expect(midLeftArrow.opacity, 1);
    expect(midRightArrow.opacity, 1);

    while (true) {
      final currentRightArrow = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(const ValueKey('palette-right-arrow')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      if (currentRightArrow.opacity == 0) {
        break;
      }
      await tester.tap(find.byTooltip('Scroll palette right'));
      await tester.pumpAndSettle();
    }

    final endLeftArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-left-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    final endRightArrow = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('palette-right-arrow')),
        matching: find.byType(AnimatedOpacity),
      ),
    );

    expect(endLeftArrow.opacity, 1);
    expect(endRightArrow.opacity, 0);
  });

  // The score reads the drop position from the drag offset; it used to be
  // the corner of the dragged symbol, so zoomed-out drops missed the staff.
  testWidgets('a dragged symbol is dropped where the finger lifts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Offset? dropped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: DragTarget<PaletteDragData>(
                  onAcceptWithDetails: (details) => dropped = details.offset,
                  builder: (_, _, _) => const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 120, child: SymbolPalette()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Quarter').first),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(const Offset(150, 140));
    await tester.pump();
    await gesture.moveTo(const Offset(150, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(dropped, const Offset(150, 100));
  });
}
