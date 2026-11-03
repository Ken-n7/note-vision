import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

Note q(String pitch, {bool chord = false, String? id}) => Note(
  step: pitch[0],
  octave: int.parse(pitch.substring(1)),
  duration: 2,
  type: 'quarter',
  isChordTone: chord,
  reviewId: id,
);

EditorState score(List<List<ScoreSymbol>> bars) => EditorState(
  score: Score(
    id: 'range',
    title: 'Range',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Piano',
        measures: [
          for (final (i, bar) in bars.indexed)
            Measure(
              number: i + 1,
              timeSignature: i == 0
                  ? const TimeSignature(beats: 4, beatType: 4)
                  : null,
              symbols: bar,
            ),
        ],
      ),
    ],
  ),
);

EditorState at(EditorState state, int measure, int symbol) => state
    .selectSymbolAt(partIndex: 0, measureIndex: measure, symbolIndex: symbol);

List<List<String>> bars(EditorState state) => [
  for (final m in state.score.parts.single.measures)
    [
      for (final s in m.symbols)
        switch (s) {
          Note(:final pitch, :final isChordTone) =>
            '${isChordTone ? '+' : ''}$pitch',
          Rest() => 'rest',
          _ => '?',
        },
    ],
];

void main() {
  final music = score([
    [q('C4', id: 'a'), q('D4'), q('E4'), q('F4')],
    [q('G4'), q('A4'), q('B4'), q('C5')],
    [],
  ]);

  test('shift and bar extension build a range across bars', () {
    var state = at(music, 0, 2);
    for (var i = 0; i < 3; i++) {
      state = state.extendSelection(1);
    }
    expect(state.rangeAnchor, (measure: 0, symbol: 2));
    expect(state.selectionPositions, [
      (measure: 0, symbol: 2),
      (measure: 0, symbol: 3),
      (measure: 1, symbol: 0),
      (measure: 1, symbol: 1),
    ]);
    state = state.extendSelectionByBar(1);
    expect(state.selectionPositions.last, (measure: 1, symbol: 3));
    // Extending back past the anchor selects from the other side.
    state = at(music, 1, 0).extendSelectionByBar(-1);
    expect(state.selectionPositions.first, (measure: 0, symbol: 0));
    expect(state.selectionPositions, hasLength(5));
    // A plain selection or any edit drops the range.
    expect(at(state, 0, 1).hasRange, isFalse);
    expect(state.moveSelectedPitch(1).hasRange, isFalse);
  });

  test('copy and paste keep bar lines, add bars and select the copy', () {
    final copied = at(music, 0, 2).extendSelection(1).extendSelection(1);
    final clipboard = copied.copySelection()!;
    expect(clipboard.bars.map((b) => b.length), [2, 1]);

    final target = music.copyWith(
      selectedPartIndex: 0,
      selectedMeasureIndex: 2,
    );
    final pasted = target.paste(clipboard);
    expect(bars(pasted).sublist(2), [
      ['E4', 'F4'],
      ['G4'],
    ]);
    expect(pasted.selectionPositions, hasLength(3));
    expect(pasted.undoStack, hasLength(1));
    expect(bars(pasted.applyUndo()), bars(music));
    // Copies carry no scan identity.
    final copy = at(music, 0, 0).copySelection()!.bars.single.single as Note;
    expect(copy.reviewId, isNull);
  });

  test('paste replaces a range and refuses to overfill a bar', () {
    final clipboard = at(music, 1, 0).copySelection()!; // G4
    final replaced = at(music, 0, 1).extendSelection(1).paste(clipboard);
    expect(bars(replaced).first, ['C4', 'G4', 'F4']);

    final full = at(music, 0, 3);
    expect(identical(full.paste(clipboard), full), isTrue);
  });

  test('delete removes the range as one step and keeps the bar', () {
    final deleted = at(music, 0, 3).extendSelection(1).deleteSelection();
    expect(bars(deleted).sublist(0, 2), [
      ['C4', 'D4', 'E4'],
      ['A4', 'B4', 'C5'],
    ]);
    expect(
      (deleted.selectedMeasureIndex, deleted.selectedSymbolIndex),
      (0, null),
    );
    expect(deleted.undoStack, hasLength(1));
  });

  test('ranges take whole chords; copies from inside a chord start one', () {
    final chords = score([
      [q('C4'), q('E4', chord: true), q('G4', chord: true), q('D4')],
    ]);
    final range = at(chords, 0, 0);
    expect(range.selectionPositions, hasLength(3));
    final fromTone = at(chords, 0, 1).extendSelection(1).copySelection()!;
    expect(
      [for (final n in fromTone.bars.single.cast<Note>()) n.isChordTone],
      [false, true],
    );
  });

  test('transposing a selection respells the rest of the bar', () {
    final state = at(
      score([
        [q('F4'), q('F4'), q('C4'), q('C4')],
      ]),
      0,
      0,
    );
    final moved = state.transposeSelection(
      const TransposeOptions(mode: TransposeMode.byInterval, interval: 1),
    );
    final notes = moved.score.parts.single.measures.single.symbols.cast<Note>();
    // F#4, then the unselected F4 needs a natural after the sharp.
    expect(
      [for (final n in notes) (n.step, n.alter)],
      [('F', 1), ('F', 0), ('C', null), ('C', null)],
    );
    expect(moved.score.parts.single.measures.single.keySignature, isNull);
  });

  test('pitch commands move every note in a range', () {
    var state = at(music, 0, 0).extendSelection(1);
    expect(EditorCommand.dot.unavailableReason(state), isNotNull);
    state = EditorCommand.pitchUp.execute(state);
    expect(bars(state).first, ['D4', 'E4', 'E4', 'F4']);
    expect(state.hasRange, isTrue);
    state = EditorCommand.octaveDown.execute(state);
    expect(bars(state).first, ['D3', 'E3', 'E4', 'F4']);
    expect(
      EditorCommand.selectAll.execute(music).selectionPositions,
      hasLength(8),
    );
    expect(EditorCommand.delete.execute(state).undoStack, hasLength(3));
  });
}
