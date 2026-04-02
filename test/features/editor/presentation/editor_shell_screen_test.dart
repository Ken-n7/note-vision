import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';
import 'package:note_vision/features/editor/presentation/widgets/symbol_palette.dart';

void main() {
  Score buildScore({bool withSymbols = true}) {
    return Score(
      id: 'score-1',
      title: 'Test Score',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [
            Measure(
              number: 1,
              symbols: withSymbols
                  ? const [
                      Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                      Rest(duration: 1, type: 'quarter'),
                    ]
                  : const [],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('renders editor shell sections and action buttons', (tester) async {
    final score = buildScore();

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    expect(find.text('Test Score'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Move Up'), findsOneWidget);
    expect(find.text('Move Down'), findsOneWidget);
    expect(find.text('Whole'), findsWidgets);
    expect(find.text('Half'), findsWidgets);
    expect(find.text('Quarter'), findsWidgets);
    expect(find.text('Eighth'), findsWidgets);
    expect(find.text('Insert Note'), findsOneWidget);
    expect(find.text('Insert Rest'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Redo'), findsOneWidget);
    expect(find.text('Zoom 100%'), findsOneWidget);
  });

  testWidgets('renders draggable symbol palette with seven items', (tester) async {
    final score = buildScore();

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('symbol-palette')), findsOneWidget);
    expect(find.text('W Rest'), findsOneWidget);
    expect(find.text('H Rest'), findsOneWidget);
    expect(find.text('Q Rest'), findsOneWidget);

    final draggables = find.byWidgetPredicate((widget) => widget is LongPressDraggable<PaletteDragData>);
    expect(draggables, findsNWidgets(7));
  });

  testWidgets('dropping palette note inserts by drop and undo restores previous state', (
    tester,
  ) async {
    final score = buildScore(withSymbols: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    await _dragPaletteItemToNotation(
      tester,
      label: 'Quarter',
      dropOffset: const Offset(88, 92),
    );

    expect(find.text('Note'), findsOneWidget);
    expect(find.text('None'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('dropping rest inserts rest and ignores pitch mapping', (tester) async {
    final score = buildScore(withSymbols: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    await _dragPaletteItemToNotation(
      tester,
      label: 'H Rest',
      dropOffset: const Offset(106, 68),
    );

    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('dropping outside measure boundary is ignored', (tester) async {
    final score = buildScore(withSymbols: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    await _dragPaletteItemToNotation(
      tester,
      label: 'Quarter',
      dropOffset: const Offset(16, 92),
    );

    expect(find.text('None'), findsOneWidget);
    expect(find.text('Note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoom controls update canvas zoom level', (tester) async {
    final score = buildScore();

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    expect(find.text('Zoom 100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('Zoom 110%'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.text('Zoom 100%'), findsOneWidget);
  });

  testWidgets('keeps insert actions enabled with default measure context', (
    tester,
  ) async {
    final score = buildScore(withSymbols: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    final moveUpButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Move Up'),
    );
    expect(moveUpButton.onPressed, isNull);

    final insertNoteButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Insert Note'),
    );
    expect(insertNoteButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Move Up'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Insert Note'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
  });

  testWidgets('tapping symbols selects, reselects, and deselects', (tester) async {
    final score = buildScore();

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    final moveUpButtonFinder = find.widgetWithText(OutlinedButton, 'Move Up');
    expect(tester.widget<OutlinedButton>(moveUpButtonFinder).onPressed, isNull);

    final notationOrigin = tester.getTopLeft(find.byType(ScoreNotationViewer));

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
    );
    await tester.pump();
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(moveUpButtonFinder).onPressed, isNotNull);

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
    );
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
    );
    await tester.pump();
    expect(find.text('None'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(moveUpButtonFinder).onPressed, isNull);
  });

  testWidgets('drag reorder updates model order and undo restores original order', (
    tester,
  ) async {
    final score = Score(
      id: 'score-reorder',
      title: 'Test Score',
      composer: 'Composer',
      parts: [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [
            Measure(
              number: 1,
              symbols: const [
                Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                Rest(duration: 1, type: 'quarter'),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(ScoreNotationViewer));
    final dragGesture = await tester.startGesture(
      origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await dragGesture.moveTo(
      origin +
          _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 2) +
          const Offset(2, 0),
    );
    await tester.pump();
    await dragGesture.up();
    await tester.pump();

    await tester.tapAt(
      origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
    );
    await tester.pump();
    expect(find.text('E4'), findsOneWidget);

    final undoButton = find.widgetWithText(OutlinedButton, 'Undo');
    await tester.ensureVisible(undoButton);
    await tester.tap(undoButton);
    await tester.pump();

    await tester.tapAt(
      origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
    );
    await tester.pump();
    expect(find.text('C4'), findsOneWidget);
  });

  testWidgets('landscape keeps controls beside notation without overlap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final score = buildScore();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorShellScreen(
          args: EditorShellArgs(
            score: score,
            initialState: EditorState(score: score),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notationRect = tester.getRect(find.byType(ScoreNotationViewer));
    final symbolLabelRect = tester.getRect(find.text('Type'));

    expect(symbolLabelRect.left, greaterThan(notationRect.right));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _dragPaletteItemToNotation(
  WidgetTester tester, {
  required String label,
  required Offset dropOffset,
}) async {
  final paletteItem = find.descendant(
    of: find.byKey(const ValueKey('symbol-palette')),
    matching: find.text(label),
  );
  expect(paletteItem, findsOneWidget);

  final notationOrigin = tester.getTopLeft(find.byType(ScoreNotationViewer));
  final gesture = await tester.startGesture(tester.getCenter(paletteItem));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  await gesture.moveTo(notationOrigin + dropOffset);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Offset _symbolCenterOffset(
  Score score, {
  required int measureIndex,
  required int symbolIndex,
}) {
  const measuresPerRow = 4;
  const minMeasureWidth = 220.0;
  const rowHeight = 140.0;
  const padding = EdgeInsets.all(16);

  final measures = score.parts.first.measures;
  final layout = const NotationLayoutCalculator().calculate(
    measures: measures,
    measuresPerRow: measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
  );

  final target = ScoreNotationPainter.buildSymbolTargets(
    measures: measures,
    measuresPerRow: layout.measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
    rowPrefixWidth: layout.rowPrefixWidth,
  ).firstWhere(
    (entry) => entry.measureIndex == measureIndex && entry.symbolIndex == symbolIndex,
  );

  return target.center;
}
