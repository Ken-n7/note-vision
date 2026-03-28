import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/editor/model/editor_snapshot.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

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

    test('measure context can exist without selected symbol', () {
      final score = _buildScore();
      final state = EditorState(score: score).copyWith(
        selectedPartIndex: 0,
        selectedMeasureIndex: 0,
      );

      expect(state.selectedPartIndex, 0);
      expect(state.selectedMeasureIndex, 0);
      expect(state.selectedSymbolIndex, isNull);
      expect(state.selectedSymbol, isNull);
    });

    test('undo and redo stacks are capped at max depth 50', () {
      final entries = List.generate(
        55,
        (index) => EditorSnapshot(
          score: _buildScore(id: 'score-$index'),
          selectedPartIndex: null,
          selectedMeasureIndex: null,
          selectedSymbolIndex: null,
          selectedSymbol: null,
          hasUnsavedChanges: false,
        ),
      );

      final state = EditorState(
        score: _buildScore(),
        undoStack: entries,
        redoStack: entries,
      );

      expect(state.undoStack.length, EditorState.maxHistoryDepth);
      expect(state.redoStack.length, EditorState.maxHistoryDepth);
      expect(state.undoStack.first.score.id, 'score-5');
      expect(state.undoStack.last.score.id, 'score-54');
      expect(state.redoStack.first.score.id, 'score-5');
      expect(state.redoStack.last.score.id, 'score-54');
    });

    test('move note can be undone and redone correctly', () {
      final original = _buildScore();
      final moved = _moveSymbol(original, fromIndex: 0, toIndex: 1);

      final edited = EditorState(score: original).applyEdit(score: moved);
      expect(_firstMeasureSymbols(edited.score).first, isA<Rest>());

      final undone = edited.undo();
      expect(_firstMeasureSymbols(undone.score).first, isA<Note>());

      final redone = undone.redo();
      expect(_firstMeasureSymbols(redone.score).first, isA<Rest>());
    });

    test('delete symbol can be undone and redone correctly', () {
      final original = _buildScore();
      final deleted = _deleteSymbol(original, atIndex: 1);

      final edited = EditorState(score: original).applyEdit(score: deleted);
      expect(_firstMeasureSymbols(edited.score).length, 1);

      final undone = edited.undo();
      expect(_firstMeasureSymbols(undone.score).length, 2);

      final redone = undone.redo();
      expect(_firstMeasureSymbols(redone.score).length, 1);
    });

    test('duration change can be undone and redone correctly', () {
      final original = _buildScore();
      final changed = _changeFirstNoteDuration(original, duration: 2);

      final edited = EditorState(score: original).applyEdit(score: changed);
      expect((_firstMeasureSymbols(edited.score).first as Note).duration, 2);

      final undone = edited.undo();
      expect((_firstMeasureSymbols(undone.score).first as Note).duration, 1);

      final redone = undone.redo();
      expect((_firstMeasureSymbols(redone.score).first as Note).duration, 2);
    });

    test('insert note can be undone and redone correctly', () {
      final original = _buildScore();
      const insertedNote = Note(
        step: 'D',
        octave: 4,
        duration: 1,
        type: 'quarter',
      );
      final inserted = _insertSymbol(original, symbol: insertedNote, atIndex: 1);

      final edited = EditorState(score: original).applyEdit(score: inserted);
      expect(_firstMeasureSymbols(edited.score).length, 3);
      expect(_firstMeasureSymbols(edited.score)[1], insertedNote);

      final undone = edited.undo();
      expect(_firstMeasureSymbols(undone.score).length, 2);

      final redone = undone.redo();
      expect(_firstMeasureSymbols(redone.score).length, 3);
      expect(_firstMeasureSymbols(redone.score)[1], insertedNote);
    });

    test('insert rest can be undone and redone correctly', () {
      final original = _buildScore();
      const insertedRest = Rest(duration: 2, type: 'half');
      final inserted = _insertSymbol(original, symbol: insertedRest, atIndex: 0);

      final edited = EditorState(score: original).applyEdit(score: inserted);
      expect(_firstMeasureSymbols(edited.score).length, 3);
      expect(_firstMeasureSymbols(edited.score).first, insertedRest);

      final undone = edited.undo();
      expect(_firstMeasureSymbols(undone.score).length, 2);
      expect(_firstMeasureSymbols(undone.score).first, isA<Note>());

      final redone = undone.redo();
      expect(_firstMeasureSymbols(redone.score).length, 3);
      expect(_firstMeasureSymbols(redone.score).first, insertedRest);
    });

    test('redo stack clears after any new edit after undo', () {
      final original = _buildScore();
      final firstEdit = _deleteSymbol(original, atIndex: 1);
      final secondEdit = _changeFirstNoteDuration(original, duration: 2);

      final afterFirstEdit = EditorState(score: original).applyEdit(score: firstEdit);
      final afterUndo = afterFirstEdit.undo();
      expect(afterUndo.redoStack, isNotEmpty);

      final afterNewEdit = afterUndo.applyEdit(score: secondEdit);
      expect(afterNewEdit.redoStack, isEmpty);
    });

    test('undo and redo on empty stacks do nothing safely', () {
      final state = EditorState(score: _buildScore());
      final afterUndo = state.undo();
      final afterRedo = state.redo();

      expect(identical(state, afterUndo), isTrue);
      expect(identical(state, afterRedo), isTrue);
    });

    test('rapid undo and redo sequences keep state uncorrupted', () {
      final original = _buildScore();
      final state1 = EditorState(score: original)
          .applyEdit(score: _changeFirstNoteDuration(original, duration: 2))
          .applyEdit(score: _insertSymbol(original, symbol: const Rest(duration: 2, type: 'half'), atIndex: 0))
          .applyEdit(score: _moveSymbol(original, fromIndex: 0, toIndex: 1));

      final state2 = state1.undo().undo().redo().undo().redo().redo();
      final symbols = _firstMeasureSymbols(state2.score);

      expect(symbols.length, 2);
      expect(symbols.first, isA<Rest>());
      expect(symbols.last, isA<Note>());
      expect(state2.undoStack.length, 3);
      expect(state2.redoStack.length, 0);
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

List<ScoreSymbol> _firstMeasureSymbols(Score score) =>
    List<ScoreSymbol>.from(score.parts[0].measures[0].symbols);

Score _moveSymbol(Score score, {required int fromIndex, required int toIndex}) {
  final symbols = List.of(score.parts[0].measures[0].symbols);
  final symbol = symbols.removeAt(fromIndex);
  symbols.insert(toIndex, symbol);
  return _replaceFirstMeasureSymbols(score, symbols);
}

Score _deleteSymbol(Score score, {required int atIndex}) {
  final symbols = List.of(score.parts[0].measures[0].symbols)..removeAt(atIndex);
  return _replaceFirstMeasureSymbols(score, symbols);
}

Score _insertSymbol(
  Score score, {
  required ScoreSymbol symbol,
  required int atIndex,
}) {
  final symbols = List.of(score.parts[0].measures[0].symbols)
    ..insert(atIndex, symbol);
  return _replaceFirstMeasureSymbols(score, symbols);
}

Score _changeFirstNoteDuration(Score score, {required int duration}) {
  final symbols = List.of(score.parts[0].measures[0].symbols);
  final note = symbols.first as Note;
  symbols[0] = Note(
    step: note.step,
    octave: note.octave,
    alter: note.alter,
    duration: duration,
    type: note.type,
    voice: note.voice,
    staff: note.staff,
  );
  return _replaceFirstMeasureSymbols(score, symbols);
}

Score _replaceFirstMeasureSymbols(Score score, List<ScoreSymbol> symbols) {
  final part = score.parts[0];
  final measure = part.measures[0];
  final updatedMeasure = Measure(
    number: measure.number,
    clef: measure.clef,
    timeSignature: measure.timeSignature,
    keySignature: measure.keySignature,
    symbols: List.of(symbols),
  );
  final updatedPart = Part(
    id: part.id,
    name: part.name,
    measures: [updatedMeasure],
  );
  return Score(
    id: score.id,
    title: score.title,
    composer: score.composer,
    parts: [updatedPart],
  );
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
