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

void main() {
  Future<void> pumpEditorShell(
    WidgetTester tester, {
    required Score score,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
  }

  InkWell actionTileForLabel(WidgetTester tester, String label) {
    final finder = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    return tester.widget<InkWell>(finder.first);
  }

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

    await pumpEditorShell(tester, score: score);

    expect(find.text('Test Score'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Whole'), findsWidgets);
    expect(find.text('Half'), findsWidgets);
    expect(find.text('Qtr'), findsOneWidget);
    expect(find.text('8th'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Rest'), findsWidgets);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
  });

  testWidgets('keeps insert actions enabled with default measure context', (
    tester,
  ) async {
    final score = buildScore(withSymbols: false);

    await pumpEditorShell(tester, score: score);

    final moveUpButton = actionTileForLabel(tester, 'Up');
    expect(moveUpButton.onTap, isNull);

    final insertNoteButton = actionTileForLabel(tester, 'Note');
    expect(insertNoteButton.onTap, isNotNull);

    await tester.tap(find.text('Up'));
    await tester.tap(find.text('Note').first);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('SELECTION'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
  });

  testWidgets('tapping symbols selects, reselects, and deselects', (tester) async {
    final score = buildScore();

    await pumpEditorShell(tester, score: score);

    final moveUpButtonFinder = find.ancestor(
      of: find.text('Up'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);

    final notationOrigin = tester.getTopLeft(find.byType(ScoreNotationViewer));

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
    );
    await tester.pump();
    expect(find.text('SELECTION'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNotNull);

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
    );
    await tester.pump();
    expect(find.text('Rest'), findsWidgets);
    expect(find.text('quarter'), findsOneWidget);

    await tester.tapAt(
      notationOrigin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
    );
    await tester.pump();
    expect(find.text('Tap a note or rest to select it'), findsOneWidget);
    expect(tester.widget<InkWell>(moveUpButtonFinder.first).onTap, isNull);
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

    await pumpEditorShell(tester, score: score);

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

    final undoButton = find.byTooltip('Undo');
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
    final score = buildScore();
    await pumpEditorShell(tester, score: score);

    final notationRect = tester.getRect(find.byType(ScoreNotationViewer));
    final symbolLabelRect = tester.getRect(find.text('SELECTION'));

    expect(symbolLabelRect.left, greaterThan(notationRect.right));
    expect(tester.takeException(), isNull);
  });
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
    parts: [measures],
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
