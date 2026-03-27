import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

void main() {
  group('EditorState', () {
    test('holds a loaded score and supports stable no-selection state', () {
      final score = _buildScore();
      final state = EditorState(score: score);

      expect(state.score.id, 'score-1');
      expect(state.selectedPartIndex, isNull);
      expect(state.selectedMeasureIndex, isNull);
      expect(state.selectedSymbolIndex, isNull);
      expect(state.selectedSymbol, isNull);
    });

    test('represents one selected symbol at a time', () {
      final score = _buildScore();
      final note = score.parts[0].measures[0].symbols[0] as Note;

      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: note,
      );

      expect(state.selectedSymbol, same(note));
      expect(state.selectedSymbol, isA<Note>());
      expect(state.selectedPartIndex, 0);
      expect(state.selectedMeasureIndex, 0);
      expect(state.selectedSymbolIndex, 0);
    });

    test('selection resets when selected symbol is removed in next score', () {
      final score = _buildScore();
      final note = score.parts[0].measures[0].symbols[0] as Note;
      final selectedState = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
        selectedSymbolIndex: 0,
        selectedSymbol: note,
      );

      final updatedScore = Score(
        id: score.id,
        title: score.title,
        composer: score.composer,
        parts: const [
          Part(
            id: 'part-1',
            name: 'Piano',
            measures: [
              Measure(
                number: 1,
                symbols: [Rest(duration: 1, type: 'quarter')],
              ),
            ],
          ),
        ],
      );

      final nextState = selectedState.copyWith(score: updatedScore);

      expect(nextState.selectedPartIndex, isNull);
      expect(nextState.selectedMeasureIndex, isNull);
      expect(nextState.selectedSymbolIndex, isNull);
      expect(nextState.selectedSymbol, isNull);
    });

    test('undo and redo stacks are capped at max depth 50', () {
      final entries = List.generate(55, (index) => _buildScore(id: 'score-$index'));

      final state = EditorState(
        score: _buildScore(),
        undoStack: entries,
        redoStack: entries,
      );

      expect(state.undoStack.length, EditorState.maxHistoryDepth);
      expect(state.redoStack.length, EditorState.maxHistoryDepth);
      expect(state.undoStack.first.id, 'score-5');
      expect(state.undoStack.last.id, 'score-54');
      expect(state.redoStack.first.id, 'score-5');
      expect(state.redoStack.last.id, 'score-54');
    });

    test('toString output is inspectable for debugging', () {
      final score = _buildScore();
      final state = EditorState(
        score: score,
        hasUnsavedChanges: true,
      );

      final debugText = state.toString();

      expect(debugText, contains('EditorState('));
      expect(debugText, contains('scoreId: score-1'));
      expect(debugText, contains('undoDepth: 0'));
      expect(debugText, contains('hasUnsavedChanges: true'));
    });

    test('sample state can be instantiated in test code', () {
      final importedScore = _buildScore(id: 'imported-score');
      final sampleState = EditorState(
        score: importedScore,
        hasUnsavedChanges: false,
      );

      expect(sampleState.score.id, 'imported-score');
      expect(sampleState.hasUnsavedChanges, isFalse);
    });
  });
}

Score _buildScore({String id = 'score-1'}) {
  return Score(
    id: id,
    title: 'Sample',
    composer: 'Composer',
    parts: const [
      Part(
        id: 'part-1',
        name: 'Piano',
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
}
