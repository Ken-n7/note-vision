import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

/// Edits must keep what they don't change: a note's dot, beam and chord link.
void main() {
  EditorState select(List<ScoreSymbol> symbols, int index, {int beats = 4}) {
    final score = Score(
      id: 's',
      title: 'T',
      composer: '',
      parts: [
        Part(id: 'P1', name: 'P1', measures: [
          Measure(
            number: 1,
            timeSignature: TimeSignature(beats: beats, beatType: 4),
            symbols: symbols,
          ),
        ]),
      ],
    );
    return EditorState(score: score).copyWith(
      selectedPartIndex: 0,
      selectedMeasureIndex: 0,
      selectedSymbolIndex: index,
      selectedSymbol: symbols[index],
    );
  }

  Note selectedNote(EditorState state) => state.selectedSymbol! as Note;

  const dottedBeamedChordTone = Note(
    step: 'E',
    octave: 4,
    duration: 3,
    type: 'quarter',
    dots: 1,
    beamed: true,
    isChordTone: true,
  );
  const base = Note(step: 'C', octave: 4, duration: 3, type: 'quarter', dots: 1);

  test('moving a note up keeps its dot, beam and chord link', () {
    final moved = select([base, dottedBeamedChordTone], 1).moveSelectedSymbolUp();
    final note = selectedNote(moved);
    expect(note.step, 'F');
    expect(note.dots, 1);
    expect(note.beamed, isTrue);
    expect(note.isChordTone, isTrue);
  });

  test('changing the accidental keeps the dot, beam and chord link', () {
    final changed =
        select([base, dottedBeamedChordTone], 1).setSelectedNoteAccidental(1);
    final note = selectedNote(changed);
    expect(note.alter, 1);
    expect(note.dots, 1);
    expect(note.beamed, isTrue);
    expect(note.isChordTone, isTrue);
  });

  test('changing the length keeps the chord link', () {
    final changed = select([
      const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      const Note(
        step: 'E',
        octave: 4,
        duration: 2,
        type: 'quarter',
        isChordTone: true,
      ),
    ], 1).setSelectedDuration(halfDuration);
    expect(selectedNote(changed).isChordTone, isTrue);
    expect(selectedNote(changed).type, 'half');
  });

  test('a note at the top of the range does not jump an octave down', () {
    const top = Note(step: 'B', octave: 7, duration: 2, type: 'quarter');
    final state = select([top], 0);
    expect(identical(state.moveSelectedSymbolUp(), state), isTrue);
  });

  test('chord tones take no time, so a full 4/4 bar with a chord is not over', () {
    // Four quarter beats, the first a two-note chord: still exactly full.
    final state = select([
      const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      const Note(
        step: 'E',
        octave: 4,
        duration: 2,
        type: 'quarter',
        isChordTone: true,
      ),
      const Note(step: 'D', octave: 4, duration: 2, type: 'quarter'),
      const Note(step: 'E', octave: 4, duration: 2, type: 'quarter'),
      const Note(step: 'F', octave: 4, duration: 2, type: 'quarter'),
    ], 4);
    // Shortening the last beat to an eighth must be allowed...
    expect(state.setSelectedDuration(eighthDuration).score,
        isNot(same(state.score)));
    // ...and two sixteenths fit in the half beat that frees up.
    final eighth = state.setSelectedDuration(eighthDuration);
    expect(
      selectedNote(eighth.setSelectedDuration(sixteenthDuration)).type,
      'sixteenth',
    );
  });

  test('an eighth can take a dot when the bar has room', () {
    final state = select([
      const Note(step: 'C', octave: 4, duration: 1, type: 'eighth'),
      const Rest(duration: 2, type: 'quarter'),
    ], 0);
    final dotted = state.toggleSelectedDot();
    expect(selectedNote(dotted).dots, 1);
    expect(selectedNote(dotted).type, 'eighth');
  });
}
