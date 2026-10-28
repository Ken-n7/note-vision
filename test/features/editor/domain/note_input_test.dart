import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

EditorState bar(List<ScoreSymbol> symbols, {Clef? clef, int? select}) {
  final state = EditorState(
    score: Score(
      id: 'input',
      title: 'Input',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Piano',
          measures: [
            Measure(
              number: 1,
              clef: clef ?? const Clef(sign: 'G', line: 2),
              timeSignature: const TimeSignature(beats: 4, beatType: 4),
              symbols: symbols,
            ),
          ],
        ),
      ],
    ),
  );
  return select == null
      ? state.copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0)
      : state.selectSymbolAt(
          partIndex: 0,
          measureIndex: 0,
          symbolIndex: select,
        );
}

Note note(String step, int octave, {bool chord = false, int? alter}) => Note(
  step: step,
  octave: octave,
  alter: alter,
  duration: 2,
  type: 'quarter',
  isChordTone: chord,
);

List<String> pitches(EditorState state, [int measure = 0]) => [
  for (final s in state.score.parts.first.measures[measure].symbols)
    switch (s) {
      Note(:final step, :final octave, :final isChordTone) =>
        '${isChordTone ? '+' : ''}$step$octave',
      Rest(:final type) => 'rest:$type',
      _ => '?',
    },
];

void main() {
  test('letters take the octave nearest the previous note', () {
    var state = bar(const []);
    for (final step in ['C', 'A', 'F', 'G']) {
      state = state.enterNote(step, quarterDuration);
    }
    // An empty treble bar starts from its middle line, B4.
    expect(pitches(state), ['C5', 'A4', 'F4', 'G4']);
    expect(state.selectedSymbolIndex, 3);

    final bass = bar(
      const [],
      clef: const Clef(sign: 'F', line: 4),
    ).enterNote('C', quarterDuration);
    expect(pitches(bass), ['C3']);
  });

  test('a full bar continues in a new bar, as one undo step', () {
    var state = bar([note('C', 5), note('D', 5), note('E', 5)], select: 2);
    state = state.enterNote('F', quarterDuration);
    expect(state.score.parts.first.measures, hasLength(1));

    final undoDepth = state.undoStack.length;
    state = state.enterNote('G', halfDuration);
    expect(state.score.parts.first.measures, hasLength(2));
    expect(pitches(state, 1), ['G5']);
    expect(state.selectedMeasureIndex, 1);
    expect(state.undoStack, hasLength(undoDepth + 1));

    state = state.enterRest(halfDuration);
    expect(pitches(state, 1), ['G5', 'rest:half']);

    state = state.applyUndo().applyUndo();
    expect(state.score.parts.first.measures, hasLength(1));
  });

  test('chord tones stack above the selected note without taking time', () {
    var state = bar([note('C', 4), note('D', 4)], select: 0);
    state = EditorCommand.addThird.execute(state);
    state = state.addChordInterval(3).addChordStep('C');
    expect(pitches(state), ['C4', '+E4', '+G4', '+C5', 'D4']);
    expect(state.selectedSymbolIndex, 3);
    expect(pitches(state.addChordStep('E')), [
      'C4',
      '+E4',
      '+G4',
      '+C5',
      '+E5',
      'D4',
    ]);
    // A pitch already in the chord is not added twice.
    final selectBase = state.selectSymbolAt(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
    );
    expect(identical(selectBase.addChordInterval(3), selectBase), isTrue);

    // New input goes after the whole chord.
    final next = selectBase.enterNote('E', quarterDuration);
    expect(pitches(next), ['C4', '+E4', '+G4', '+C5', 'E4', 'D4']);
    expect(
      EditorCommand.addThird.unavailableReason(
        bar([const Rest(duration: 2, type: 'quarter')], select: 0),
      ),
      'Select a note',
    );
  });

  test('deleting a chord base keeps the rest of the chord together', () {
    final state = bar([
      note('C', 4),
      note('E', 4, chord: true),
      note('G', 4, chord: true),
      note('D', 4),
    ], select: 0).deleteSelectedSymbol();
    expect(pitches(state), ['E4', '+G4', 'D4']);
    expect(state.selectedSymbolIndex, 0);
  });

  test('a letter re-pitches the selected note near its current pitch', () {
    final state = bar([note('C', 5, alter: 1)], select: 0);
    final changed = state.setSelectedNoteStep('A');
    expect(pitches(changed), ['A4']);
    expect((changed.selectedSymbol as Note).alter, isNull);
    expect(identical(state.setSelectedNoteStep('X'), state), isTrue);
  });
}
