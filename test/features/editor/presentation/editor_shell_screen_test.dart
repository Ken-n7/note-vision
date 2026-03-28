import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/presentation/editor_shell_screen.dart';

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
    expect(find.text('W'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
    expect(find.text('Q'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('Insert Note'), findsOneWidget);
    expect(find.text('Insert Rest'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Redo'), findsOneWidget);
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

    await tester.tapAt(notationOrigin + const Offset(154, 68));
    await tester.pump();
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('C4'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(moveUpButtonFinder).onPressed, isNotNull);

    await tester.tapAt(notationOrigin + const Offset(190, 68));
    await tester.pump();
    expect(find.text('Rest'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    await tester.tapAt(notationOrigin + const Offset(190, 68));
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
    final dragGesture = await tester.startGesture(origin + const Offset(146, 68));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await dragGesture.moveTo(origin + const Offset(198, 68));
    await tester.pump();
    await dragGesture.up();
    await tester.pump();

    await tester.tapAt(origin + const Offset(146, 68));
    await tester.pump();
    expect(find.text('E4'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
    await tester.pump();

    await tester.tapAt(origin + const Offset(146, 68));
    await tester.pump();
    expect(find.text('C4'), findsOneWidget);
  });
}
