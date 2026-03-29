import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

void main() {
  group('Editor shell end-to-end flows', () {
    testWidgets('supports full Sprint 5 flow for imported score source', (tester) async {
      await _runFullFlow(
        tester,
        score: _importedScore(),
      );
    });

    testWidgets('supports full Sprint 5 flow for mapped score source', (tester) async {
      await _runFullFlow(
        tester,
        score: _mappedScore(),
      );
    });
  });
}

Future<void> _runFullFlow(
  WidgetTester tester, {
  required Score score,
}) async {
  var expected = EditorState(score: score).copyWith(
    selectedPartIndex: 0,
    selectedMeasureIndex: 0,
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

  // Select note then rest and verify status strip updates.
  await tester.tapAt(origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 0));
  await tester.pump();
  expected = _select(expected, measureIndex: 0, symbolIndex: 0);
  expect(find.text('Note'), findsOneWidget);
  expect(find.text('B4'), findsOneWidget);

  await tester.tapAt(origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 1));
  await tester.pump();
  expected = _select(expected, measureIndex: 0, symbolIndex: 1);
  expect(find.text('Rest'), findsOneWidget);

  // Drag reorder within measure then undo/redo.
  final dragGesture = await tester.startGesture(
    origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 0),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  await dragGesture.moveTo(
    origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 2) + const Offset(2, 0),
  );
  await tester.pump();
  await dragGesture.up();
  await tester.pump();
  expected = expected.reorderSymbolWithinMeasure(
    measureIndex: 0,
    fromSymbolIndex: 0,
    toSymbolIndex: 2,
  );

  await _tapActionButton(tester, 'Undo');
  expected = expected.applyUndo();

  await _tapActionButton(tester, 'Redo');
  expected = expected.applyRedo();

  // Re-select moved B4 note and validate pitch movement boundaries.
  await tester.tapAt(origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 2));
  await tester.pump();
  expected = _select(expected, measureIndex: 0, symbolIndex: 2);
  expect(find.text('B4'), findsOneWidget);

  await _tapActionButton(tester, 'Move Up');
  expected = expected.moveSelectedSymbolUp();
  expect(find.text('C5'), findsOneWidget);

  await _tapActionButton(tester, 'Move Down');
  expected = expected.moveSelectedSymbolDown();
  expect(find.text('B4'), findsOneWidget);

  // Duration change across all supported values for note.
  await _tapActionButton(tester, 'Whole');
  expected = expected.setSelectedDuration(wholeDuration);
  expect(find.text('whole'), findsOneWidget);

  await _tapActionButton(tester, 'Half');
  expected = expected.setSelectedDuration(halfDuration);
  expect(find.text('half'), findsOneWidget);

  await _tapActionButton(tester, 'Quarter');
  expected = expected.setSelectedDuration(quarterDuration);
  expect(find.text('quarter'), findsOneWidget);

  await _tapActionButton(tester, 'Eighth');
  expected = expected.setSelectedDuration(eighthDuration);
  expect(find.text('eighth'), findsOneWidget);

  // Insert note/rest and verify auto-selection.
  await _tapActionButton(tester, 'Insert Note');
  expected = expected.insertNoteAfterSelection();
  expect(find.text('Note'), findsOneWidget);

  await _tapActionButton(tester, 'Insert Rest');
  expected = expected.insertRestAfterSelection();
  expect(find.text('Rest'), findsOneWidget);

  // Select a rest and validate duration updates.
  await tester.tapAt(origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: 0));
  await tester.pump();
  expected = _select(expected, measureIndex: 0, symbolIndex: 0);
  expect(find.text('Rest'), findsOneWidget);

  await _tapActionButton(tester, 'Whole');
  expected = expected.setSelectedDuration(wholeDuration);
  expect(find.text('whole'), findsOneWidget);

  await _tapActionButton(tester, 'Half');
  expected = expected.setSelectedDuration(halfDuration);
  expect(find.text('half'), findsOneWidget);

  await _tapActionButton(tester, 'Quarter');
  expected = expected.setSelectedDuration(quarterDuration);
  expect(find.text('quarter'), findsOneWidget);

  await _tapActionButton(tester, 'Eighth');
  expected = expected.setSelectedDuration(eighthDuration);
  expect(find.text('eighth'), findsOneWidget);

  // Delete selected rest then delete a note; validate no crash and consistent state.
  await _tapActionButton(tester, 'Delete');
  expected = expected.deleteSelectedSymbol();

  var noteIndex = _firstNoteIndexOrNull(expected.score, measureIndex: 0);
  if (noteIndex == null) {
    await _tapActionButton(tester, 'Insert Note');
    expected = expected.insertNoteAfterSelection();
    noteIndex = expected.selectedSymbolIndex ?? 0;
  }
  await tester.tapAt(origin + _symbolCenterOffset(expected.score, measureIndex: 0, symbolIndex: noteIndex));
  await tester.pump();
  expected = _select(expected, measureIndex: 0, symbolIndex: noteIndex);

  await _tapActionButton(tester, 'Delete');
  expected = expected.deleteSelectedSymbol();

  // Multiple sequential edits and no crash on empty-measure flow.
  await _tapActionButton(tester, 'Insert Note');
  expected = expected.insertNoteAfterSelection();
  await _tapActionButton(tester, 'Delete');
  expected = expected.deleteSelectedSymbol();
  await _tapActionButton(tester, 'Insert Rest');
  expected = expected.insertRestAfterSelection();

  // Undo/Redo should remain functional after sequential edits.
  await _tapActionButton(tester, 'Undo');
  expected = expected.applyUndo();
  await _tapActionButton(tester, 'Redo');
  expected = expected.applyRedo();

  expect(tester.takeException(), isNull);
  expect(expected.score.parts.first.measures.first.symbols, isNotEmpty);
}

EditorState _select(
  EditorState state, {
  required int measureIndex,
  required int symbolIndex,
}) {
  final symbol = state.score.parts.first.measures[measureIndex].symbols[symbolIndex];
  return state.copyWith(
    selectedPartIndex: 0,
    selectedMeasureIndex: measureIndex,
    selectedSymbolIndex: symbolIndex,
    selectedSymbol: symbol,
  );
}

Future<void> _tapActionButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(OutlinedButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

int? _firstNoteIndexOrNull(Score score, {required int measureIndex}) {
  final symbols = score.parts.first.measures[measureIndex].symbols;
  final index = symbols.indexWhere((symbol) => symbol is Note);
  return index == -1 ? null : index;
}

Score _importedScore() {
  return const Score(
    id: 'imported-e2e',
    title: 'Imported E2E',
    composer: 'QA',
    parts: [
      Part(
        id: 'P1',
        name: 'Piano',
        measures: [
          Measure(
            number: 1,
            symbols: [
              Note(step: 'B', octave: 4, duration: 1, type: 'quarter'),
              Rest(duration: 1, type: 'quarter'),
              Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
            ],
          ),
          Measure(number: 2, symbols: [Rest(duration: 1, type: 'quarter')]),
        ],
      ),
    ],
  );
}

Score _mappedScore() {
  return const Score(
    id: 'mapped-e2e',
    title: '',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Detected Part',
        measures: [
          Measure(
            number: 1,
            symbols: [
              Note(step: 'B', octave: 4, duration: 1, type: 'quarter', staff: 1),
              Rest(duration: 1, type: 'quarter', staff: 1),
              Note(step: 'C', octave: 4, duration: 1, type: 'quarter', staff: 1),
            ],
          ),
          Measure(number: 2, symbols: [Rest(duration: 1, type: 'quarter', staff: 1)]),
        ],
      ),
    ],
  );
}

Offset _symbolCenterOffset(
  Score score, {
  required int measureIndex,
  required int symbolIndex,
}) {
  const measuresPerRow = 4;
  const minMeasureWidth = 140.0;
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
