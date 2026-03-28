import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
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

  testWidgets('disables edit actions and remains stable with no selection', (tester) async {
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Move Up'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Insert Note'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
  });
}
