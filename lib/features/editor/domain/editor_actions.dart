import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

class DurationSpec {
  const DurationSpec(this.type, this.divisions);

  final String type;
  final int divisions;
}

const DurationSpec wholeDuration = DurationSpec('whole', 4);
const DurationSpec halfDuration = DurationSpec('half', 2);
const DurationSpec quarterDuration = DurationSpec('quarter', 1);
const DurationSpec eighthDuration = DurationSpec('eighth', 1);

extension EditorActions on EditorState {
  bool get hasSelection =>
      selectedPartIndex != null &&
      selectedMeasureIndex != null &&
      selectedSymbolIndex != null &&
      selectedSymbol != null;

  bool get canUndo => undoStack.isNotEmpty;

  bool get canRedo => redoStack.isNotEmpty;

  EditorState moveSelectedSymbolUp() {
    if (!hasSelection || selectedSymbol is! Note) return this;
    final note = selectedSymbol as Note;
    final moved = _moveNoteByScaleStep(note, 1);
    return _replaceSelectedSymbol(moved);
  }

  EditorState moveSelectedSymbolDown() {
    if (!hasSelection || selectedSymbol is! Note) return this;
    final note = selectedSymbol as Note;
    final moved = _moveNoteByScaleStep(note, -1);
    return _replaceSelectedSymbol(moved);
  }

  EditorState setSelectedDuration(DurationSpec durationSpec) {
    if (!hasSelection) return this;

    final symbol = selectedSymbol;
    if (symbol is Note) {
      return _replaceSelectedSymbol(
        Note(
          step: symbol.step,
          octave: symbol.octave,
          alter: symbol.alter,
          duration: durationSpec.divisions,
          type: durationSpec.type,
          voice: symbol.voice,
          staff: symbol.staff,
        ),
      );
    }

    if (symbol is Rest) {
      return _replaceSelectedSymbol(
        Rest(
          duration: durationSpec.divisions,
          type: durationSpec.type,
          voice: symbol.voice,
          staff: symbol.staff,
        ),
      );
    }

    return this;
  }

  EditorState insertNoteAfterSelection() {
    final note = selectedSymbol is Note
        ? selectedSymbol as Note
        : const Note(step: 'C', octave: 4, duration: 1, type: 'quarter');

    final newNote = Note(
      step: note.step,
      octave: note.octave,
      alter: note.alter,
      duration: note.duration,
      type: note.type,
      voice: note.voice,
      staff: note.staff,
    );

    if (!hasSelection) {
      return _insertWithoutSelection(newNote);
    }

    return _insertAfterSelection(newNote);
  }

  EditorState insertRestAfterSelection() {
    final rest = selectedSymbol is Rest
        ? selectedSymbol as Rest
        : const Rest(duration: 1, type: 'quarter');

    final newRest = Rest(
      duration: rest.duration,
      type: rest.type,
      voice: rest.voice,
      staff: rest.staff,
    );

    if (!hasSelection) {
      return _insertWithoutSelection(newRest);
    }

    return _insertAfterSelection(newRest);
  }

  EditorState deleteSelectedSymbol() {
    if (!hasSelection) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final symbols = List<ScoreSymbol>.from(
      score.parts[partIndex].measures[measureIndex].symbols,
    );
    symbols.removeAt(symbolIndex);

    final nextScore = _replaceMeasureSymbols(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbols: symbols,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: null,
      selectedMeasureIndex: null,
      selectedSymbolIndex: null,
      selectedSymbol: null,
      clearSelection: true,
    );
  }

  EditorState applyUndo() => undo();

  EditorState applyRedo() => redo();

  EditorState _replaceSelectedSymbol(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final symbols = List<ScoreSymbol>.from(
      score.parts[partIndex].measures[measureIndex].symbols,
    );
    symbols[symbolIndex] = symbol;

    final nextScore = _replaceMeasureSymbols(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbols: symbols,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: symbolIndex,
      selectedSymbol: symbol,
    );
  }

  EditorState _insertAfterSelection(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final insertIndex = selectedSymbolIndex! + 1;

    final symbols = List<ScoreSymbol>.from(
      score.parts[partIndex].measures[measureIndex].symbols,
    );
    symbols.insert(insertIndex, symbol);

    final nextScore = _replaceMeasureSymbols(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbols: symbols,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: insertIndex,
      selectedSymbol: symbol,
    );
  }

  EditorState _insertWithoutSelection(ScoreSymbol symbol) {
    if (score.parts.isEmpty || score.parts.first.measures.isEmpty) {
      return this;
    }

    const partIndex = 0;
    const measureIndex = 0;
    final symbols = List<ScoreSymbol>.from(
      score.parts[partIndex].measures[measureIndex].symbols,
    );
    symbols.add(symbol);
    final insertIndex = symbols.length - 1;

    final nextScore = _replaceMeasureSymbols(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbols: symbols,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: insertIndex,
      selectedSymbol: symbol,
    );
  }

  Score _replaceMeasureSymbols({
    required int partIndex,
    required int measureIndex,
    required List<ScoreSymbol> symbols,
  }) {
    final parts = List<Part>.from(score.parts);
    final measures = List<Measure>.from(parts[partIndex].measures);
    final currentMeasure = measures[measureIndex];

    measures[measureIndex] = Measure(
      number: currentMeasure.number,
      clef: currentMeasure.clef,
      timeSignature: currentMeasure.timeSignature,
      keySignature: currentMeasure.keySignature,
      symbols: symbols,
    );

    final currentPart = parts[partIndex];
    parts[partIndex] = Part(
      id: currentPart.id,
      name: currentPart.name,
      measures: measures,
    );

    return Score(
      id: score.id,
      title: score.title,
      composer: score.composer,
      parts: parts,
    );
  }
}

Note _moveNoteByScaleStep(Note note, int steps) {
  const stepsByName = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  final currentIndex = stepsByName.indexOf(note.step);
  if (currentIndex == -1) return note;

  var nextIndex = currentIndex + steps;
  var nextOctave = note.octave;

  while (nextIndex < 0) {
    nextIndex += stepsByName.length;
    nextOctave -= 1;
  }

  while (nextIndex >= stepsByName.length) {
    nextIndex -= stepsByName.length;
    nextOctave += 1;
  }

  return Note(
    step: stepsByName[nextIndex],
    octave: nextOctave.clamp(0, 9),
    alter: note.alter,
    duration: note.duration,
    type: note.type,
    voice: note.voice,
    staff: note.staff,
  );
}
