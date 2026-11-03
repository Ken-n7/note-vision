import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

// Spelling is checked against MuseScore in test/musescore_parity.
void main() {
  const source = SourceRegion(
    pageId: 'scan',
    x: .1,
    y: .2,
    width: .05,
    height: .1,
  );
  final score = Score(
    id: 's',
    title: 'Scan',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Piano',
        measures: [
          Measure(
            number: 1,
            reviewId: 'm1',
            source: source,
            symbols: [
              Note(
                step: 'C',
                octave: 4,
                duration: 1,
                type: 'eighth',
                beams: const {1: BeamValue.begin},
                reviewId: 'n1',
                source: source,
                confidence: .9,
              ),
              const Note(
                step: 'F',
                octave: 4,
                alter: 1,
                duration: 1,
                type: 'eighth',
                beams: {1: BeamValue.end},
              ),
              const Rest(duration: 2, type: 'quarter', reviewId: 'r1'),
            ],
          ),
        ],
      ),
    ],
  );

  test('keeps scan evidence and writes a key where none was written', () {
    final moved = const Transposer().transpose(
      score,
      const TransposeOptions(mode: TransposeMode.toKey, targetKey: 2),
    );
    final measure = moved.parts.single.measures.single;
    expect(measure.keySignature?.fifths, 2);
    expect(measure.reviewId, 'm1');
    expect(measure.source, source);
    final first = measure.symbols[0] as Note;
    expect((first.pitch, first.alter), ('D4', null));
    expect(
      (first.reviewId, first.source, first.confidence),
      ('n1', source, .9),
    );
    expect(first.beams, {1: BeamValue.begin});
    // F#4 up a major second is G#4, which D major does not give.
    final second = measure.symbols[1] as Note;
    expect((second.step, second.octave, second.alter), ('G', 4, 1));
    expect(
      measure.symbols[2],
      same(score.parts.single.measures.single.symbols[2]),
    );
  });

  test('the editor transposes as one undo step and keeps the selection', () {
    final state = EditorState(
      score: score,
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    final moved = state.transposeScore(
      const TransposeOptions(mode: TransposeMode.byInterval, interval: 25),
    );
    expect((moved.selectedSymbol as Note).pitch, 'C5');
    expect(moved.selectedSymbolIndex, 0);
    expect(moved.undoStack, hasLength(1));
    expect(identical(moved.applyUndo().score, score), isTrue);
  });
}
