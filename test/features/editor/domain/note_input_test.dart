import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/score_timeline.dart';
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

    // New input goes after the whole chord, writing over D4.
    final next = selectBase.enterNote('E', quarterDuration);
    expect(pitches(next), ['C4', '+E4', '+G4', '+C5', 'E4']);
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

  test('another voice starts where the selected note starts', () {
    Note half(String step) =>
        Note(step: step, octave: 5, duration: 4, type: 'half');
    var state = bar([half('C'), half('D')], select: 1);
    state = state.enterNote('G', quarterDuration, voice: 2);
    final symbols = state.score.parts.first.measures.first.symbols;
    // A half rest fills voice 2 up to beat 3, where D5 starts.
    expect(symbols[2], isA<Rest>());
    expect(
      ((symbols[2] as Rest).type, (symbols[2] as Rest).voice),
      ('half', 2),
    );
    expect(((symbols[3] as Note).pitch, (symbols[3] as Note).voice), ('G5', 2));
    expect(state.selectedSymbolIndex, 3);
    // Without a voice, input continues the selected note's voice.
    state = state.enterNote('A', quarterDuration);
    expect((state.selectedSymbol as Note).voice, 2);
    final timeline = const ScoreTimelineBuilder().measure(state.score, 0, 0);
    expect(timeline.symbols.last.onset, MusicalTime(3));
    // Voice 2 is full, so the next note starts the next bar.
    state = state.enterNote('B', quarterDuration);
    expect(state.selectedMeasureIndex, 1);
    expect((state.selectedSymbol as Note).voice, 2);
    expect(state.undoStack, hasLength(3));

    // From the first note, voice 2 starts at the bar line with no rests.
    final fromStart = bar([
      half('C'),
      half('D'),
    ], select: 0).enterNote('E', quarterDuration, voice: 2);
    expect(fromStart.score.parts.first.measures.first.symbols, hasLength(3));
  });

  test('a letter re-pitches the selected note near its current pitch', () {
    final state = bar([note('C', 5, alter: 1)], select: 0);
    final changed = state.setSelectedNoteStep('A');
    expect(pitches(changed), ['A4']);
    expect((changed.selectedSymbol as Note).alter, isNull);
    expect(identical(state.setSelectedNoteStep('X'), state), isTrue);
  });

  group('note input writes over what follows, as in MuseScore', () {
    const quarterRest = Rest(duration: 2, type: 'quarter');
    const halfRest = Rest(duration: 4, type: 'half');

    test('a selected rest is written over; a bar of rests fills up', () {
      var state = bar([halfRest, halfRest], select: 0);
      state = state.enterNote('C', quarterDuration);
      expect(pitches(state), ['C5', 'rest:quarter', 'rest:half']);
      state = state.enterNote('D', quarterDuration);
      expect(pitches(state), ['C5', 'D5', 'rest:half']);
      // With nothing selected, input starts after the bar's last note.
      final fresh = bar([
        quarterRest,
        quarterRest,
      ]).enterNote('E', quarterDuration);
      expect(pitches(fresh), ['E5', 'rest:quarter']);
    });

    test('a note partly written over leaves rests for its time', () {
      final state = bar([
        Note(step: 'C', octave: 5, duration: 4, type: 'half'),
        Note(step: 'D', octave: 5, duration: 4, type: 'half'),
      ], select: 0).enterNote('E', quarterDuration);
      expect(pitches(state), ['C5', 'E5', 'rest:quarter']);
      expect(state.selectedSymbolIndex, 1);
    });

    test('a value longer than the bar is tied into the next bar', () {
      var state = bar([note('C', 5), note('D', 5), note('E', 5)], select: 2);
      final depth = state.undoStack.length;
      state = state.enterNote('F', halfDuration);
      // A quarter in this bar, tied to a quarter at the start of a new one.
      expect(pitches(state), ['C5', 'D5', 'E5', 'F5']);
      expect(pitches(state, 1), ['F5']);
      final first = state.score.parts.first.measures[0].symbols.last as Note;
      final second = state.score.parts.first.measures[1].symbols.first as Note;
      expect((first.type, second.type), ('quarter', 'quarter'));
      expect(
        state.score.spanners,
        contains(Spanner(SpannerKind.tie, first.reviewId!, second.reviewId!)),
      );
      expect((state.selectedMeasureIndex, state.selectedSymbolIndex), (1, 0));
      expect(state.undoStack, hasLength(depth + 1));
      expect(state.applyUndo().score.parts.first.measures, hasLength(1));
    });

    test('a pickup rest is written over and keeps the pickup short', () {
      final state = EditorState(
        score: Score(
          id: 'p',
          title: 'P',
          composer: '',
          parts: [
            Part(
              id: 'P1',
              name: 'Voice',
              measures: [
                const Measure(
                  number: 0,
                  implicit: true,
                  clef: Clef(sign: 'G', line: 2),
                  timeSignature: TimeSignature(beats: 4, beatType: 4),
                  symbols: [quarterRest],
                ),
                const Measure(number: 1, symbols: []),
              ],
            ),
          ],
        ),
      ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
      final next = state.enterNote('G', halfDuration);
      // A quarter fills the pickup and is tied into bar 1.
      expect(pitches(next), ['G4']);
      expect(pitches(next, 1), ['G4']);
      expect(next.score.spanners, hasLength(1));
    });

    test('ties and slurs of notes written over are removed', () {
      final tied = [
        note('C', 5).copyWith(reviewId: 'a'),
        note('C', 5).copyWith(reviewId: 'b'),
      ];
      final state = bar(tied, select: 0);
      final withTie = state.copyWith(
        score: state.score.copyWith(
          spanners: const [Spanner(SpannerKind.tie, 'a', 'b')],
        ),
      );
      expect(withTie.enterNote('E', quarterDuration).score.spanners, isEmpty);
    });
  });
}
