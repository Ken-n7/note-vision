import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

void main() {
  group('EditorActions', () {
    test('move up/down is diatonic with octave transitions and preserves alter', () {
      final upState = _selectedState(
        const Note(
          step: 'B',
          octave: 4,
          alter: -1,
          duration: 1,
          type: 'quarter',
        ),
      );

      final movedUp = upState.moveSelectedSymbolUp();
      final movedUpNote = movedUp.selectedSymbol! as Note;
      expect(movedUpNote.step, 'C');
      expect(movedUpNote.octave, 5);
      expect(movedUpNote.alter, -1);

      final downState = _selectedState(
        const Note(
          step: 'C',
          octave: 4,
          alter: 1,
          duration: 1,
          type: 'quarter',
        ),
      );

      final movedDown = downState.moveSelectedSymbolDown();
      final movedDownNote = movedDown.selectedSymbol! as Note;
      expect(movedDownNote.step, 'B');
      expect(movedDownNote.octave, 3);
      expect(movedDownNote.alter, 1);
    });

    test('move up/down no-ops when selected symbol is rest', () {
      final state = _selectedState(const Rest(duration: 1, type: 'quarter'));

      expect(identical(state.moveSelectedSymbolUp(), state), isTrue);
      expect(identical(state.moveSelectedSymbolDown(), state), isTrue);
    });

    test('duration change to same value is a no-op and does not push undo', () {
      final state = _selectedState(
        const Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
      );

      final next = state.setSelectedDuration(quarterDuration);

      expect(identical(next, state), isTrue);
      expect(next.undoStack, isEmpty);
    });

    test('insert note/rest append to end of selected measure and auto-select', () {
      final score = Score(
        id: 's1',
        title: 't',
        composer: 'c',
        parts: const [
          Part(
            id: 'p1',
            name: 'P1',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final withInsertedNote = state.insertNoteAfterSelection();
      final noteSymbols = withInsertedNote.score.parts[0].measures[0].symbols;
      expect(noteSymbols.last, isA<Note>());
      expect((noteSymbols.last as Note).pitch, 'C4');
      expect(withInsertedNote.selectedSymbolIndex, noteSymbols.length - 1);

      final withInsertedRest = withInsertedNote.insertRestAfterSelection();
      final restSymbols = withInsertedRest.score.parts[0].measures[0].symbols;
      expect(restSymbols.last, isA<Rest>());
      expect((restSymbols.last as Rest).type, 'quarter');
      expect(withInsertedRest.selectedSymbolIndex, restSymbols.length - 1);
    });

    test('insert note/rest no-op with no measure context', () {
      final score = _baseScore(const []);
      final state = EditorState(score: score);

      expect(identical(state.insertNoteAfterSelection(), state), isTrue);
      expect(identical(state.insertRestAfterSelection(), state), isTrue);
    });

    test('deleting last symbol keeps measure context so insert can recover', () {
      final score = _baseScore(
        const [Note(step: 'C', octave: 4, duration: 1, type: 'quarter')],
      );
      final selectedState = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: score.parts[0].measures[0].symbols[0],
      );

      final cleared = selectedState.deleteSelectedSymbol();
      expect(cleared.selectedPartIndex, 0);
      expect(cleared.selectedMeasureIndex, 0);
      expect(cleared.selectedSymbolIndex, isNull);
      expect(cleared.selectedSymbol, isNull);

      final restored = cleared.insertNoteAfterSelection();
      expect(restored.score.parts[0].measures[0].symbols, hasLength(1));
      expect(restored.score.parts[0].measures[0].symbols.first, isA<Note>());
    });
  });
}

EditorState _selectedState(ScoreSymbol symbol) {
  final score = _baseScore([symbol]);
  return EditorState(score: score).copyWith(
    selectedPartIndex: 0,
    selectedMeasureIndex: 0,
    selectedSymbolIndex: 0,
    selectedSymbol: score.parts[0].measures[0].symbols[0],
  );
}

Score _baseScore(List<ScoreSymbol> symbols) => Score(
  id: 'score-1',
  title: 'Sample',
  composer: 'Composer',
  parts: [
    Part(
      id: 'part-1',
      name: 'Piano',
      measures: [
        Measure(
          number: 1,
          symbols: symbols,
        ),
      ],
    ),
  ],
);
