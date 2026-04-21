import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

void main() {
  group('Mapped score editor regression', () {
    test(
      'mapped multi-measure symbols remain editable with stable selection',
      () {
        final score = _mappedScore();
        final selectedSymbol = score.parts[0].measures[0].symbols[0];
        final selectedState = EditorState(score: score).copyWith(
          selectedPartIndex: 0,
          selectedMeasureIndex: 0,
          selectedSymbolIndex: 0,
          selectedSymbol: selectedSymbol,
        );

        final reordered = selectedState.reorderSymbolWithinMeasure(
          measureIndex: 0,
          fromSymbolIndex: 0,
          toSymbolIndex: 2,
        );

        expect(reordered.selectedPartIndex, 0);
        expect(reordered.selectedMeasureIndex, 0);
        expect(reordered.selectedSymbolIndex, 2);
        expect((reordered.selectedSymbol! as Note).pitch, 'E4');

        final movedToNextMeasure = reordered.moveSelectedSymbolToMeasureOffset(
          1,
        );
        expect(movedToNextMeasure.selectedMeasureIndex, 1);
        expect(movedToNextMeasure.selectedSymbolIndex, 1);
        expect((movedToNextMeasure.selectedSymbol! as Note).pitch, 'E4');

        final deleted = movedToNextMeasure.deleteSelectedSymbol();
        expect(deleted.selectedMeasureIndex, 1);
        expect(deleted.selectedSymbolIndex, 0);
        expect(deleted.selectedSymbol, isA<Rest>());

        final inserted = deleted.insertNoteAfterSelection();
        expect(inserted.selectedMeasureIndex, 1);
        expect(inserted.selectedSymbolIndex, 1);
        expect(inserted.selectedSymbol, isA<Note>());
        expect(inserted.score.parts[0].measures[1].symbols, hasLength(2));
      },
    );

    test(
      'partial mapped-style score with unresolved symbols keeps safe empty selection',
      () {
        final score = Score(
          id: 'mapped-partial',
          title: '',
          composer: '',
          parts: const [
            Part(
              id: 'P1',
              name: 'Detected Part',
              measures: [
                Measure(number: 1, symbols: []),
                Measure(
                  number: 2,
                  symbols: [Rest(duration: 1, type: 'quarter')],
                ),
              ],
            ),
          ],
        );

        final state = EditorState(score: score);

        expect(state.selectedPartIndex, isNull);
        expect(state.selectedMeasureIndex, isNull);
        expect(state.selectedSymbolIndex, isNull);
        expect(state.selectedSymbol, isNull);

        final selected = state.copyWith(
          selectedPartIndex: 0,
          selectedMeasureIndex: 1,
          selectedSymbolIndex: 0,
          selectedSymbol: score.parts[0].measures[1].symbols[0],
        );

        expect(selected.selectedMeasureIndex, 1);
        expect(selected.selectedSymbolIndex, 0);
        expect(selected.selectedSymbol, isA<Rest>());
      },
    );
  });
}

Score _mappedScore() {
  return const Score(
    id: 'mapped-regression',
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
              Note(
                step: 'E',
                octave: 4,
                duration: 1,
                type: 'quarter',
                staff: 1,
              ),
              Rest(duration: 2, type: 'half', staff: 1),
              Note(
                step: 'G',
                octave: 4,
                duration: 1,
                type: 'quarter',
                staff: 1,
              ),
            ],
          ),
          Measure(
            number: 2,
            symbols: [Rest(duration: 1, type: 'quarter', staff: 1)],
          ),
        ],
      ),
    ],
  );
}
