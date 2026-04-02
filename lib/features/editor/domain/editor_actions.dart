import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
// import 'package:note_vision/core/models/score.dart';
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
      final isSameDuration =
          symbol.duration == durationSpec.divisions &&
          symbol.type == durationSpec.type;
      if (isSameDuration) return this;
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
      final isSameDuration =
          symbol.duration == durationSpec.divisions &&
          symbol.type == durationSpec.type;
      if (isSameDuration) return this;
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
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    return _appendToSelectedMeasure(
      const Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
    );
  }

  EditorState insertRestAfterSelection() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    return _appendToSelectedMeasure(
      const Rest(duration: 1, type: 'quarter'),
    );
  }

  EditorState deleteSelectedSymbol() {
    if (!hasSelection) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final currentSymbols = score.parts[partIndex].measures[measureIndex].symbols;
    final symbols = List<ScoreSymbol>.from(currentSymbols)..removeAt(symbolIndex);
    final nextScore = score.deleteSymbolAt(partIndex, measureIndex, symbolIndex);

    if (symbols.isEmpty) {
      return applyEdit(
        score: nextScore,
        selectedPartIndex: partIndex,
        selectedMeasureIndex: measureIndex,
        selectedSymbolIndex: null,
        selectedSymbol: null,
      );
    }

    final nextIndex = symbolIndex.clamp(0, symbols.length - 1);
    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: nextIndex,
      selectedSymbol: symbols[nextIndex],
    );
  }

  EditorState applyUndo() => undo();

  EditorState applyRedo() => redo();

  EditorState moveSelectedSymbolToMeasureOffset(int offset) {
    if (!hasSelection || offset == 0) return this;

    final partIndex = selectedPartIndex!;
    final fromMeasureIndex = selectedMeasureIndex!;
    final toMeasureIndex = fromMeasureIndex + offset;
    final measures = score.parts[partIndex].measures;
    if (toMeasureIndex < 0 || toMeasureIndex >= measures.length) return this;

    final fromSymbols = List<ScoreSymbol>.from(measures[fromMeasureIndex].symbols);
    final toSymbols = List<ScoreSymbol>.from(measures[toMeasureIndex].symbols);
    final fromSymbolIndex = selectedSymbolIndex!;
    if (fromSymbolIndex < 0 || fromSymbolIndex >= fromSymbols.length) return this;

    final moved = fromSymbols[fromSymbolIndex];
    final withoutSource = score.deleteSymbolAt(
      partIndex,
      fromMeasureIndex,
      fromSymbolIndex,
    );
    final toInsertIndex = score.parts[partIndex].measures[toMeasureIndex].symbols.length;
    final nextScore = withoutSource.insertSymbolAt(
      partIndex,
      toMeasureIndex,
      toInsertIndex,
      moved,
    );
    final toSymbolIndex = toSymbols.length;

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: toMeasureIndex,
      selectedSymbolIndex: toSymbolIndex,
      selectedSymbol: moved,
    );
  }

  EditorState reorderSymbolWithinMeasure({
    required int measureIndex,
    required int fromSymbolIndex,
    required int toSymbolIndex,
  }) {
    if (score.parts.isEmpty) return this;
    final partIndex = 0;
    final measures = score.parts[partIndex].measures;
    if (measureIndex < 0 || measureIndex >= measures.length) return this;

    final currentSymbols = measures[measureIndex].symbols;
    if (fromSymbolIndex < 0 || fromSymbolIndex >= currentSymbols.length) return this;
    if (toSymbolIndex < 0 || toSymbolIndex >= currentSymbols.length) return this;
    if (fromSymbolIndex == toSymbolIndex) return this;

    final nextScore = score.reorderSymbol(
      partIndex,
      measureIndex,
      fromSymbolIndex,
      toSymbolIndex,
    );
    final symbols = nextScore.parts[partIndex].measures[measureIndex].symbols;

    final selectedPart = selectedPartIndex;
    final selectedMeasure = selectedMeasureIndex;
    final selectedIndex = selectedSymbolIndex;
    final selected = selectedSymbol;

    if (selectedPart != partIndex ||
        selectedMeasure != measureIndex ||
        selectedIndex == null ||
        selected == null) {
      return applyEdit(
        score: nextScore,
        selectedPartIndex: selectedPartIndex,
        selectedMeasureIndex: selectedMeasureIndex,
        selectedSymbolIndex: selectedSymbolIndex,
        selectedSymbol: selectedSymbol,
      );
    }

    int nextSelectedIndex = selectedIndex;

    if (selectedIndex == fromSymbolIndex) {
      nextSelectedIndex = toSymbolIndex;
    } else if (fromSymbolIndex < selectedIndex && toSymbolIndex >= selectedIndex) {
      nextSelectedIndex = selectedIndex - 1;
    } else if (fromSymbolIndex > selectedIndex && toSymbolIndex <= selectedIndex) {
      nextSelectedIndex = selectedIndex + 1;
    }

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: nextSelectedIndex,
      selectedSymbol: symbols[nextSelectedIndex],
    );
  }

  EditorState insertSymbolAtMeasureIndex({
    required int measureIndex,
    required int insertIndex,
    required ScoreSymbol symbol,
  }) {
    if (score.parts.isEmpty) return this;
    const partIndex = 0;
    final measures = score.parts[partIndex].measures;
    if (measureIndex < 0 || measureIndex >= measures.length) return this;
    if (insertIndex < 0 || insertIndex > measures[measureIndex].symbols.length) return this;

    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: insertIndex,
      selectedSymbol: symbol,
    );
  }

  EditorState _replaceSelectedSymbol(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final nextScore = score.replaceSymbolAt(
      partIndex,
      measureIndex,
      symbolIndex,
      symbol,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: symbolIndex,
      selectedSymbol: symbol,
    );
  }

  EditorState _appendToSelectedMeasure(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;

    final insertIndex = score.parts[partIndex].measures[measureIndex].symbols.length;
    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return applyEdit(
      score: nextScore,
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: insertIndex,
      selectedSymbol: symbol,
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
    octave: nextOctave.clamp(1, 7),
    alter: note.alter,
    duration: note.duration,
    type: note.type,
    voice: note.voice,
    staff: note.staff,
  );
}
