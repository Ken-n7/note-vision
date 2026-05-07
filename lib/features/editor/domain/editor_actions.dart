import 'package:note_vision/core/models/clef.dart';
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

const DurationSpec wholeDuration = DurationSpec('whole', 8);
const DurationSpec halfDuration = DurationSpec('half', 4);
const DurationSpec quarterDuration = DurationSpec('quarter', 2);
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
      const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
    );
  }

  EditorState insertRestAfterSelection() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    return _appendToSelectedMeasure(const Rest(duration: 2, type: 'quarter'));
  }

  EditorState deleteSelectedMeasureIfEmpty() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final measures = score.parts[partIndex].measures;
    if (measures.length <= 1) return this; // keep at least one measure
    if (measures[measureIndex].symbols.isNotEmpty) return this; // not empty

    final nextScore = score.deleteMeasureFromAllParts(measureIndex);
    final nextMeasureIndex = (measureIndex - 1).clamp(
      0,
      nextScore.parts[partIndex].measures.length - 1,
    );
    return applyEditWithMeasureContext(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: nextMeasureIndex,
    );
  }

  EditorState addMeasureAfterSelected() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;
    final measureIndex = selectedMeasureIndex!;
    final nextScore = score.insertMeasureAfterInAllParts(measureIndex);
    final newMeasureIndex = measureIndex + 1;
    return applyEditWithMeasureContext(
      score: nextScore,
      partIndex: selectedPartIndex!,
      measureIndex: newMeasureIndex,
    );
  }

  EditorState addPageAtEnd() {
    if (score.parts.isEmpty) return this;
    final updatedParts = <Part>[];
    for (final part in score.parts) {
      updatedParts.add(
        Part(
          id: part.id,
          name: part.name,
          measures: [
            ...part.measures,
            Measure(
              number: part.measures.length + 1,
              symbols: const [],
              startsNewPage: true,
            ),
          ],
        ),
      );
    }
    final newMeasureIndex = score.parts.isEmpty
        ? 0
        : score.parts.first.measures.length;
    return applyEditWithMeasureContext(
      score: Score(
        id: score.id,
        title: score.title,
        composer: score.composer,
        parts: updatedParts,
      ),
      partIndex: selectedPartIndex ?? 0,
      measureIndex: newMeasureIndex,
    );
  }

  EditorState setSelectedMeasureClef(Clef? clef) {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final currentClef = score.parts[partIndex].measures[measureIndex].clef;
    if (currentClef == clef) return this;

    final nextScore = score.setMeasureClef(partIndex, measureIndex, clef);
    return applyEditPreservingSelection(
      score: nextScore,
    );
  }

  EditorState deleteSelectedSymbol() {
    if (!hasSelection) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final currentSymbols =
        score.parts[partIndex].measures[measureIndex].symbols;
    final symbols = List<ScoreSymbol>.from(currentSymbols)
      ..removeAt(symbolIndex);
    final nextScore = score.deleteSymbolAt(
      partIndex,
      measureIndex,
      symbolIndex,
    );

    if (symbols.isEmpty) {
      return applyEditWithMeasureContext(
        score: nextScore,
        partIndex: partIndex,
        measureIndex: measureIndex,
      );
    }

    final nextIndex = symbolIndex.clamp(0, symbols.length - 1);
    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: nextIndex,
      symbol: symbols[nextIndex],
    );
  }

  EditorState applyUndo() => undo();

  EditorState applyRedo() => redo();

  /// Sets the `alter` value of the selected note.
  /// [alter] = 1 (♯), -1 (♭), 0 (♮), null (none). No-op for rests.
  EditorState setSelectedNoteAccidental(int? alter) {
    if (!hasSelection || selectedSymbol is! Note) return this;
    final note = selectedSymbol as Note;
    if (note.alter == alter) return this;
    return _replaceSelectedSymbol(
      Note(
        step: note.step,
        octave: note.octave,
        alter: alter,
        duration: note.duration,
        type: note.type,
        voice: note.voice,
        staff: note.staff,
      ),
    );
  }

  EditorState moveSelectedSymbolToMeasureOffset(int offset) {
    if (!hasSelection || offset == 0) return this;

    final partIndex = selectedPartIndex!;
    final fromMeasureIndex = selectedMeasureIndex!;
    final toMeasureIndex = fromMeasureIndex + offset;
    final measures = score.parts[partIndex].measures;
    if (toMeasureIndex < 0 || toMeasureIndex >= measures.length) return this;

    final fromSymbols = List<ScoreSymbol>.from(
      measures[fromMeasureIndex].symbols,
    );
    final toSymbols = List<ScoreSymbol>.from(measures[toMeasureIndex].symbols);
    final fromSymbolIndex = selectedSymbolIndex!;
    if (fromSymbolIndex < 0 || fromSymbolIndex >= fromSymbols.length) {
      return this;
    }

    final moved = fromSymbols[fromSymbolIndex];
    final withoutSource = score.deleteSymbolAt(
      partIndex,
      fromMeasureIndex,
      fromSymbolIndex,
    );
    final toInsertIndex =
        score.parts[partIndex].measures[toMeasureIndex].symbols.length;
    final nextScore = withoutSource.insertSymbolAt(
      partIndex,
      toMeasureIndex,
      toInsertIndex,
      moved,
    );
    final toSymbolIndex = toSymbols.length;

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: toMeasureIndex,
      symbolIndex: toSymbolIndex,
      symbol: moved,
    );
  }

  EditorState moveSymbolToDest({
    required int fromPartIndex,
    required int fromMeasureIndex,
    required int fromSymbolIndex,
    required int toPartIndex,
    required int toMeasureIndex,
    required int toSymbolIndex,
  }) {
    if (score.parts.isEmpty) return this;
    if (fromPartIndex < 0 || fromPartIndex >= score.parts.length) return this;
    if (toPartIndex < 0 || toPartIndex >= score.parts.length) return this;
    final fromMeasures = score.parts[fromPartIndex].measures;
    final toMeasures = score.parts[toPartIndex].measures;
    if (fromMeasureIndex < 0 || fromMeasureIndex >= fromMeasures.length) {
      return this;
    }
    if (toMeasureIndex < 0 || toMeasureIndex >= toMeasures.length) return this;
    if (fromSymbolIndex < 0 ||
        fromSymbolIndex >= fromMeasures[fromMeasureIndex].symbols.length) {
      return this;
    }

    final sameMeasure =
        fromPartIndex == toPartIndex && fromMeasureIndex == toMeasureIndex;

    if (sameMeasure) {
      final symbolCount = fromMeasures[fromMeasureIndex].symbols.length;
      final clampedTo = toSymbolIndex.clamp(0, symbolCount - 1);
      if (fromSymbolIndex == clampedTo) return this;
      final nextScore = score.reorderSymbol(
        fromPartIndex,
        fromMeasureIndex,
        fromSymbolIndex,
        clampedTo,
      );
      final symbols =
          nextScore.parts[fromPartIndex].measures[fromMeasureIndex].symbols;
      return applyEditWithSymbolSelection(
        score: nextScore,
        partIndex: fromPartIndex,
        measureIndex: fromMeasureIndex,
        symbolIndex: clampedTo,
        symbol: symbols[clampedTo],
      );
    }

    // Cross-measure move: delete from source, insert at destination.
    final moved = fromMeasures[fromMeasureIndex].symbols[fromSymbolIndex];
    final withoutSource = score.deleteSymbolAt(
      fromPartIndex,
      fromMeasureIndex,
      fromSymbolIndex,
    );
    final destCount = withoutSource
        .parts[toPartIndex]
        .measures[toMeasureIndex]
        .symbols
        .length;
    final clampedTo = toSymbolIndex.clamp(0, destCount);
    final nextScore = withoutSource.insertSymbolAt(
      toPartIndex,
      toMeasureIndex,
      clampedTo,
      moved,
    );

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: toPartIndex,
      measureIndex: toMeasureIndex,
      symbolIndex: clampedTo,
      symbol: moved,
    );
  }

  EditorState reorderSymbolWithinMeasure({
    required int measureIndex,
    required int fromSymbolIndex,
    required int toSymbolIndex,
  }) {
    if (score.parts.isEmpty) return this;
    final partIndex = selectedPartIndex ?? 0;
    final measures = score.parts[partIndex].measures;
    if (measureIndex < 0 || measureIndex >= measures.length) return this;

    final currentSymbols = measures[measureIndex].symbols;
    if (fromSymbolIndex < 0 || fromSymbolIndex >= currentSymbols.length) {
      return this;
    }
    if (toSymbolIndex < 0 || toSymbolIndex >= currentSymbols.length) {
      return this;
    }
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
      return applyEditPreservingSelection(
        score: nextScore,
      );
    }

    int nextSelectedIndex = selectedIndex;

    if (selectedIndex == fromSymbolIndex) {
      nextSelectedIndex = toSymbolIndex;
    } else if (fromSymbolIndex < selectedIndex &&
        toSymbolIndex >= selectedIndex) {
      nextSelectedIndex = selectedIndex - 1;
    } else if (fromSymbolIndex > selectedIndex &&
        toSymbolIndex <= selectedIndex) {
      nextSelectedIndex = selectedIndex + 1;
    }

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: nextSelectedIndex,
      symbol: symbols[nextSelectedIndex],
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

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: symbolIndex,
      symbol: symbol,
    );
  }

  EditorState insertSymbolAtMeasureIndex({
    int partIndex = 0,
    required int measureIndex,
    required int insertIndex,
    required ScoreSymbol symbol,
  }) {
    if (score.parts.isEmpty) return this;
    if (partIndex < 0 || partIndex >= score.parts.length) return this;
    final measures = score.parts[partIndex].measures;
    if (measureIndex < 0 || measureIndex >= measures.length) return this;
    if (insertIndex < 0 || insertIndex > measures[measureIndex].symbols.length) {
      return this;
    }

    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: insertIndex,
      symbol: symbol,
    );
  }

  EditorState _appendToSelectedMeasure(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;

    final insertIndex =
        score.parts[partIndex].measures[measureIndex].symbols.length;
    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return applyEditWithSymbolSelection(
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: insertIndex,
      symbol: symbol,
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
