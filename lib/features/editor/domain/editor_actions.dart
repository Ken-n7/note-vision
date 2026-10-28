import 'dart:math' as math;

import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/staff_pitch_mapper.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

class DurationSpec {
  const DurationSpec(this.type, this.divisions);

  final String type;
  final int divisions;
}

enum EditorEditIntent {
  replaceSelection,
  appendToMeasure,
  insertAfterSelection,
  insertAtTarget,
  moveSelectionAcrossMeasures,
  reorderWithinMeasure,
  deleteSelection,
  updateMeasureMetadata,
  createMeasure,
  createPage,
  deleteMeasure,
  transpose,
}

const DurationSpec wholeDuration = DurationSpec('whole', 8);
const DurationSpec halfDuration = DurationSpec('half', 4);
const DurationSpec quarterDuration = DurationSpec('quarter', 2);
const DurationSpec eighthDuration = DurationSpec('eighth', 1);

/// The stored duration counts 2 divisions per quarter, so a sixteenth is
/// stored as 1; its real length comes from its type (see [quarterLength]).
const DurationSpec sixteenthDuration = DurationSpec('sixteenth', 1);

/// One staff in a new part order: an existing part ([from] is its index) or
/// a new empty one with [clef]. [name] may rename it. [joinsPrevious] makes
/// it a further staff of the entry above (a piano's left hand).
typedef StaffPlanEntry = ({
  int? from,
  String name,
  Clef? clef,
  bool joinsPrevious,
});

/// Notes and rests copied from one part, bar by bar (empty bars included,
/// so pasted music keeps its bar lines).
class EditorClipboard {
  const EditorClipboard(this.bars);
  final List<List<ScoreSymbol>> bars;
  int get symbolCount => bars.fold(0, (n, bar) => n + bar.length);
}

extension EditorActions on EditorState {
  bool get hasSelection => hasSymbolSelection;

  bool get hasEditableSelection => hasEditableSymbolSelection;

  bool get canUndo => undoStack.isNotEmpty;

  bool get canRedo => redoStack.isNotEmpty;

  int get musicSymbolCount => score.parts.fold(
    0,
    (count, part) =>
        count +
        part.measures.fold(
          0,
          (count, measure) =>
              count +
              measure.symbols
                  .where((symbol) => symbol is Note || symbol is Rest)
                  .length,
        ),
  );

  /// One undo step for the entire score; keep the current measure available
  /// for insertion without retaining a selection of a removed symbol.
  EditorState clearAllSymbols() {
    final cleared = score.clearAllMusicSymbols();
    if (identical(cleared, score)) return this;
    return applyEdit(
      score: cleared,
      selectedPartIndex: selectedPartIndex,
      selectedMeasureIndex: selectedMeasureIndex,
    );
  }

  EditorState selectSymbolAt({
    required int partIndex,
    required int measureIndex,
    required int symbolIndex,
  }) {
    final parts = score.parts;
    if (parts.isEmpty || partIndex < 0 || partIndex >= parts.length) {
      return copyWith(clearSelection: true);
    }

    final measures = parts[partIndex].measures;
    if (measureIndex < 0 || measureIndex >= measures.length) {
      return copyWith(clearSelection: true);
    }

    final symbols = measures[measureIndex].symbols;
    if (symbolIndex < 0 || symbolIndex >= symbols.length) {
      return clearSymbolSelectionPreservingMeasureContext();
    }

    return copyWith(
      selectedPartIndex: partIndex,
      selectedMeasureIndex: measureIndex,
      selectedSymbolIndex: symbolIndex,
      selectedSymbol: symbols[symbolIndex],
    );
  }

  EditorState clearSymbolSelectionPreservingMeasureContext() {
    return copyWith(selectedSymbolIndex: null, selectedSymbol: null);
  }

  EditorState deleteSymbolAtSelectionTarget({
    required int partIndex,
    required int measureIndex,
    required int symbolIndex,
  }) {
    final selected = selectSymbolAt(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: symbolIndex,
    );
    if (!selected.hasEditableSelection) {
      return this;
    }
    return selected.deleteSelectedSymbol();
  }

  EditorState moveSelectedSymbolUp() {
    if (!hasSelection || selectedSymbol is! Note) return this;
    final note = selectedSymbol as Note;
    final moved = _moveNoteByScaleStep(note, 1);
    if (identical(moved, note)) return this;
    return _replaceSelectedSymbol(
      moved,
      intent: EditorEditIntent.replaceSelection,
    );
  }

  EditorState moveSelectedSymbolDown() {
    if (!hasSelection || selectedSymbol is! Note) return this;
    final note = selectedSymbol as Note;
    final moved = _moveNoteByScaleStep(note, -1);
    if (identical(moved, note)) return this;
    return _replaceSelectedSymbol(
      moved,
      intent: EditorEditIntent.replaceSelection,
    );
  }

  bool canMoveSelectedPitch(int steps) {
    final note = selectedSymbol;
    return hasEditableSelection &&
        note is Note &&
        !identical(_moveNoteByScaleStep(note, steps), note);
  }

  /// Diatonic movement keeps the written accidental and all rhythm evidence.
  EditorState moveSelectedPitch(int steps) {
    if (!canMoveSelectedPitch(steps)) return this;
    return _replaceSelectedSymbol(
      _moveNoteByScaleStep(selectedSymbol as Note, steps),
      intent: EditorEditIntent.replaceSelection,
    );
  }

  /// Replacing one member of a chord with a rest would change its timeline.
  /// Chord-wide replacement belongs to the upcoming range-editing commands.
  bool get canConvertSelectedNoteToRest {
    final note = selectedSymbol;
    if (!hasEditableSelection || note is! Note || note.isChordTone) {
      return false;
    }
    final symbols =
        score.parts[selectedPartIndex!].measures[selectedMeasureIndex!].symbols;
    final nextIndex = selectedSymbolIndex! + 1;
    return nextIndex >= symbols.length ||
        symbols[nextIndex] is! Note ||
        !(symbols[nextIndex] as Note).isChordTone;
  }

  EditorState convertSelectedNoteToRest() {
    if (!canConvertSelectedNoteToRest) return this;
    final note = selectedSymbol as Note;
    return _replaceSelectedSymbol(
      Rest(
        duration: note.duration,
        type: note.type,
        dots: note.dots,
        voice: note.voice,
        staff: note.staff,
        reviewId: note.reviewId,
        source: note.source,
        tuplet: note.tuplet,
      ),
      intent: EditorEditIntent.replaceSelection,
    );
  }

  EditorState convertSelectedRestToNote() {
    if (!hasEditableSelection || selectedSymbol is! Rest) return this;
    final rest = selectedSymbol as Rest;
    return _replaceSelectedSymbol(
      Note(
        step: 'C',
        octave: 4,
        duration: rest.duration,
        type: rest.type,
        dots: rest.dots,
        voice: rest.voice,
        staff: rest.staff,
        reviewId: rest.reviewId,
        source: rest.source,
        tuplet: rest.tuplet,
      ),
      intent: EditorEditIntent.replaceSelection,
    );
  }

  bool canSetSelectedDuration(DurationSpec spec) =>
      hasEditableSelection &&
      _canReplaceSelectedSymbolWith(
        quarterLength(spec.type, 0, spec.divisions) * _selectedTupletFactor,
      );

  /// A tuplet member keeps its tuplet when its value changes.
  double get _selectedTupletFactor => switch (selectedEditableSymbol) {
    Note(:final tuplet) || Rest(:final tuplet) => tuplet?.factor ?? 1,
    _ => 1,
  };

  bool get canToggleSelectedDot {
    final symbol = selectedEditableSymbol;
    if (symbol == null) return false;
    final (type, dots, duration) = switch (symbol) {
      Note(:final type, :final dots, :final duration) ||
      Rest(:final type, :final dots, :final duration) => (type, dots, duration),
      _ => ('', 0, 0),
    };
    return noteValueQuarters.containsKey(type) &&
        _canReplaceSelectedSymbolWith(
          quarterLength(type, dots > 0 ? 0 : 1, duration) *
              _selectedTupletFactor,
        );
  }

  EditorState setSelectedDuration(DurationSpec durationSpec) {
    if (!hasSelection) return this;

    final symbol = selectedSymbol;
    if (!canSetSelectedDuration(durationSpec)) {
      return this;
    }
    if (symbol is Note) {
      final isSameDuration =
          symbol.duration == durationSpec.divisions &&
          symbol.type == durationSpec.type &&
          symbol.dots == 0;
      if (isSameDuration) return this;
      final canBeam =
          durationSpec.type == 'eighth' || durationSpec.type == 'sixteenth';
      return _replaceSelectedSymbol(
        symbol.copyWith(
          duration: durationSpec.divisions,
          type: durationSpec.type,
          dots: 0,
          beamed: canBeam && symbol.beamed,
          beams: canBeam
              ? {
                  for (final entry in symbol.beams.entries)
                    if (entry.key <= (durationSpec.type == 'eighth' ? 1 : 2))
                      entry.key: entry.value,
                }
              : const {},
          confidence: null,
        ),
        intent: EditorEditIntent.replaceSelection,
      );
    }

    if (symbol is Rest) {
      final isSameDuration =
          symbol.duration == durationSpec.divisions &&
          symbol.type == durationSpec.type &&
          symbol.dots == 0;
      if (isSameDuration) return this;
      return _replaceSelectedSymbol(
        symbol.copyWith(
          duration: durationSpec.divisions,
          type: durationSpec.type,
          dots: 0,
          confidence: null,
        ),
        intent: EditorEditIntent.replaceSelection,
      );
    }

    return this;
  }

  EditorState applyBeamEdits(List<ScoreSymbol> symbols) {
    if (!hasMeasureContext) return this;
    final p = selectedPartIndex!;
    final m = selectedMeasureIndex!;
    final current = score.parts[p].measures[m].symbols;
    if (current.length != symbols.length) return this;
    var next = score;
    for (var i = 0; i < symbols.length; i++) {
      if (!identical(current[i], symbols[i])) {
        next = next.replaceSymbolAt(p, m, i, symbols[i]);
      }
    }
    if (identical(next, score)) return this;
    final index = selectedSymbolIndex;
    if (index != null) {
      return applyEditWithSymbolSelection(
        score: next,
        partIndex: p,
        measureIndex: m,
        symbolIndex: index,
        symbol: next.getSymbolAt(p, m, index)!,
      );
    }
    return applyEditWithMeasureContext(
      score: next,
      partIndex: p,
      measureIndex: m,
    );
  }

  EditorState toggleSelectedDot() {
    if (!hasSelection) return this;
    final symbol = selectedSymbol;

    final type = symbol is Note
        ? symbol.type.trim().toLowerCase()
        : symbol is Rest
        ? symbol.type.trim().toLowerCase()
        : null;
    if (type == null || noteValueQuarters[type] == null) return this;

    final currentDots = symbol is Note ? symbol.dots : (symbol as Rest).dots;
    final newDots = currentDots > 0 ? 0 : 1;
    final storedDuration = symbol is Note
        ? symbol.duration
        : (symbol as Rest).duration;
    final newQuarters = quarterLength(type, newDots, storedDuration);
    // The stored duration (2 per quarter) can't hold a dotted eighth or
    // sixteenth exactly; timing uses the type and dots.
    final newDuration = (newQuarters * 2).round().clamp(1, 1 << 20);

    if (!canToggleSelectedDot) return this;

    if (symbol is Note) {
      return _replaceSelectedSymbol(
        symbol.copyWith(
          duration: newDuration,
          dots: newDots,
          beamed: symbol.beamed,
          confidence: null,
        ),
        intent: EditorEditIntent.replaceSelection,
      );
    }

    if (symbol is Rest) {
      return _replaceSelectedSymbol(
        symbol.copyWith(
          duration: newDuration,
          dots: newDots,
          confidence: null,
        ),
        intent: EditorEditIntent.replaceSelection,
      );
    }

    return this;
  }

  EditorState insertNoteAfterSelection() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    return _insertAfterSelectionOrAppend(
      const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      intent: EditorEditIntent.insertAfterSelection,
    );
  }

  EditorState insertRestAfterSelection() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    return _insertAfterSelectionOrAppend(
      const Rest(duration: 2, type: 'quarter'),
      intent: EditorEditIntent.insertAfterSelection,
    );
  }

  EditorState deleteSelectedMeasure() {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final measures = score.parts[partIndex].measures;
    if (measures.length <= 1) return this; // keep at least one measure

    final nextScore = score.deleteMeasureFromAllParts(measureIndex);
    final nextMeasureIndex = (measureIndex - 1).clamp(
      0,
      nextScore.parts[partIndex].measures.length - 1,
    );
    return _applyMeasureContextEdit(
      intent: EditorEditIntent.deleteMeasure,
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
    return _applyMeasureContextEdit(
      intent: EditorEditIntent.createMeasure,
      score: nextScore,
      partIndex: selectedPartIndex!,
      measureIndex: newMeasureIndex,
    );
  }

  EditorState appendMeasureAtEnd() {
    if (score.parts.isEmpty) return this;
    final lastMeasureIndex = score.parts.first.measures.length - 1;
    final nextScore = score.insertMeasureAfterInAllParts(lastMeasureIndex);
    return _applyMeasureContextEdit(
      intent: EditorEditIntent.createMeasure,
      score: nextScore,
      partIndex: selectedPartIndex ?? 0,
      measureIndex: lastMeasureIndex + 1,
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
          staff: part.staff,
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
    return _applyMeasureContextEdit(
      intent: EditorEditIntent.createPage,
      score: score.copyWith(parts: updatedParts),
      partIndex: selectedPartIndex ?? 0,
      measureIndex: newMeasureIndex,
    );
  }

  /// Sets the time signature from the selected measure on, in every part.
  EditorState setTimeSignatureAtSelectedMeasure(TimeSignature timeSignature) {
    if (selectedMeasureIndex == null) return this;
    // Already in force there: nothing to change or undo.
    if (selectedMeasureTimeSignature == timeSignature) return this;
    final nextScore = score.setTimeSignatureAt(
      selectedMeasureIndex!,
      timeSignature,
    );
    if (identical(nextScore, score)) return this;
    return _applySelectionPreservingEdit(
      intent: EditorEditIntent.updateMeasureMetadata,
      score: nextScore,
    );
  }

  /// The time signature in force at the selected measure.
  TimeSignature? get selectedMeasureTimeSignature {
    if (selectedMeasureIndex == null || score.parts.isEmpty) return null;
    final part = (selectedPartIndex ?? 0).clamp(0, score.parts.length - 1);
    if (selectedMeasureIndex! >= score.parts[part].measures.length) return null;
    return _activeTimeSignatureForMeasure(
      partIndex: part,
      measureIndex: selectedMeasureIndex!,
    );
  }

  EditorState setSelectedMeasureClef(Clef? clef) {
    if (selectedPartIndex == null || selectedMeasureIndex == null) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final currentClef = score.parts[partIndex].measures[measureIndex].clef;
    if (currentClef == clef) return this;

    final nextScore = score.setMeasureClef(partIndex, measureIndex, clef);
    return _applySelectionPreservingEdit(
      intent: EditorEditIntent.updateMeasureMetadata,
      score: nextScore,
    );
  }

  EditorState setPartClef(Clef newClef) {
    if (selectedPartIndex == null) return this;

    final partIndex = selectedPartIndex!;
    final part = score.parts[partIndex];
    if (part.measures.isEmpty) return this;

    final oldClef = part.measures.first.clef ?? const Clef(sign: 'G', line: 2);
    if (oldClef.sign == newClef.sign && oldClef.line == newClef.line) {
      return this;
    }

    final updatedMeasures = part.measures.asMap().entries.map((entry) {
      final i = entry.key;
      final measure = entry.value;

      final updatedSymbols = measure.symbols.map((symbol) {
        if (symbol is! Note) return symbol;
        final newPitch = StaffPitchMapper.recalculatePitch(
          step: symbol.step,
          octave: symbol.octave,
          oldClefSign: oldClef.sign,
          oldClefLine: oldClef.line,
          newClefSign: newClef.sign,
          newClefLine: newClef.line,
        );
        return symbol.copyWith(
          step: newPitch.step,
          octave: newPitch.octave,
          beamed: symbol.beamed,
          confidence: null,
        );
      }).toList();

      return Measure(
        number: measure.number,
        reviewId: measure.reviewId,
        source: measure.source,
        clef: i == 0 ? newClef : null,
        timeSignature: measure.timeSignature,
        keySignature: measure.keySignature,
        symbols: updatedSymbols,
        startsNewPage: measure.startsNewPage,
        startsNewSystem: measure.startsNewSystem,
        leftBarlineType: measure.leftBarlineType,
        rightBarlineType: measure.rightBarlineType,
      );
    }).toList();

    final updatedParts = List<Part>.from(score.parts)
      ..[partIndex] = Part(
        id: part.id,
        name: part.name,
        staff: part.staff,
        measures: updatedMeasures,
      );

    final nextScore = score.copyWith(parts: updatedParts);

    return _applySelectionPreservingEdit(
      intent: EditorEditIntent.updateMeasureMetadata,
      score: nextScore,
    );
  }

  EditorState deleteSelectedSymbol() {
    if (!hasEditableSelection) return this;

    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final currentSymbols =
        score.parts[partIndex].measures[measureIndex].symbols;
    final symbols = List<ScoreSymbol>.from(currentSymbols)
      ..removeAt(symbolIndex);
    var nextScore = score.deleteSymbolAt(partIndex, measureIndex, symbolIndex);
    // The chord's next tone becomes its main note, so the remaining tones do
    // not join the preceding note.
    final removed = currentSymbols[symbolIndex];
    final tone = symbolIndex < symbols.length ? symbols[symbolIndex] : null;
    if (removed is Note &&
        !removed.isChordTone &&
        tone is Note &&
        tone.isChordTone) {
      symbols[symbolIndex] = _pitched(
        tone,
        _diatonic(tone),
        alter: tone.alter,
        isChordTone: false,
        beams: removed.beams,
      );
      nextScore = nextScore.replaceSymbolAt(
        partIndex,
        measureIndex,
        symbolIndex,
        symbols[symbolIndex],
      );
    }

    if (symbols.isEmpty) {
      return _applyMeasureContextEdit(
        intent: EditorEditIntent.deleteSelection,
        score: nextScore,
        partIndex: partIndex,
        measureIndex: measureIndex,
      );
    }

    final nextIndex = symbolIndex.clamp(0, symbols.length - 1);
    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.deleteSelection,
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: nextIndex,
      symbol: symbols[nextIndex],
    );
  }

  // ── Range selection and clipboard ────────────────────────────────────

  bool get hasRange => rangeAnchor != null;

  /// Notes and rests from the range anchor to the selection in reading
  /// order, with the chord tones of the last chord; else the selected symbol
  /// and its chord tones. Empty without a selection.
  List<SymbolPosition> get selectionPositions {
    if (!hasEditableSelection) return const [];
    final measures = score.parts[selectedPartIndex!].measures;
    final current = (
      measure: selectedMeasureIndex!,
      symbol: selectedSymbolIndex!,
    );
    var (start, end) = (rangeAnchor ?? current, current);
    if (start.measure > end.measure ||
        (start.measure == end.measure && start.symbol > end.symbol)) {
      (start, end) = (end, start);
    }
    final positions = <SymbolPosition>[];
    for (var m = start.measure; m <= end.measure; m++) {
      final symbols = measures[m].symbols;
      var last = m == end.measure ? end.symbol : symbols.length - 1;
      if (m == end.measure) {
        while (last + 1 < symbols.length &&
            symbols[last + 1] is Note &&
            (symbols[last + 1] as Note).isChordTone) {
          last++;
        }
      }
      for (var i = m == start.measure ? start.symbol : 0; i <= last; i++) {
        if (symbols[i] is Note || symbols[i] is Rest) {
          positions.add((measure: m, symbol: i));
        }
      }
    }
    return positions;
  }

  /// Every note and rest of [partIndex] in reading order.
  List<SymbolPosition> _editablePositions(int partIndex) => [
    for (final (m, measure) in score.parts[partIndex].measures.indexed)
      for (final (i, symbol) in measure.symbols.indexed)
        if (symbol is Note || symbol is Rest) (measure: m, symbol: i),
  ];

  /// Moves the selected end of the range to [to], anchoring the other end at
  /// the current selection when there is no range yet.
  EditorState _extendTo(SymbolPosition to) {
    final anchor =
        rangeAnchor ??
        (measure: selectedMeasureIndex!, symbol: selectedSymbolIndex!);
    return copyWith(
      selectedMeasureIndex: to.measure,
      selectedSymbolIndex: to.symbol,
      selectedSymbol: score
          .parts[selectedPartIndex!]
          .measures[to.measure]
          .symbols[to.symbol],
      rangeAnchor: anchor,
    );
  }

  EditorState _selectSpan(
    int partIndex,
    SymbolPosition from,
    SymbolPosition to,
  ) {
    final selected = selectSymbolAt(
      partIndex: partIndex,
      measureIndex: from.measure,
      symbolIndex: from.symbol,
    );
    return from == to ? selected : selected._extendTo(to);
  }

  /// Shift + arrow: extends the range by one note or rest.
  EditorState extendSelection(int direction) {
    if (!hasEditableSelection) return this;
    final positions = _editablePositions(selectedPartIndex!);
    final index =
        positions.indexOf((
          measure: selectedMeasureIndex!,
          symbol: selectedSymbolIndex!,
        )) +
        direction;
    if (index < 0 || index >= positions.length) return this;
    return _extendTo(positions[index]);
  }

  /// Ctrl + Shift + arrow: extends to the edge of this bar, then by bars.
  EditorState extendSelectionByBar(int direction) {
    if (!hasEditableSelection) return this;
    final positions = _editablePositions(selectedPartIndex!);
    var measure = selectedMeasureIndex!;
    while (true) {
      final inBar = positions.where((p) => p.measure == measure);
      if (inBar.isNotEmpty) {
        final edge = direction > 0 ? inBar.last : inBar.first;
        if (edge.symbol != selectedSymbolIndex ||
            measure != selectedMeasureIndex) {
          return _extendTo(edge);
        }
      }
      measure += direction;
      if (measure < 0 || measure > positions.last.measure) return this;
    }
  }

  /// Shift + tap: extends the range to a symbol in the same part.
  EditorState extendSelectionTo({
    required int partIndex,
    required int measureIndex,
    required int symbolIndex,
  }) {
    final symbol = score.getSymbolAt(partIndex, measureIndex, symbolIndex);
    if (symbol is! Note && symbol is! Rest) return this;
    if (!hasEditableSelection || partIndex != selectedPartIndex) {
      return selectSymbolAt(
        partIndex: partIndex,
        measureIndex: measureIndex,
        symbolIndex: symbolIndex,
      );
    }
    return _extendTo((measure: measureIndex, symbol: symbolIndex));
  }

  /// Ctrl + A: every note and rest in the selected part (the first part
  /// when nothing is selected).
  EditorState selectAllInPart() {
    if (score.parts.isEmpty) return this;
    final part = selectedPartIndex ?? 0;
    final positions = _editablePositions(part);
    if (positions.isEmpty) return this;
    return _selectSpan(part, positions.first, positions.last);
  }

  /// Every note and rest in the selected bar.
  EditorState selectBar() {
    if (!hasMeasureContext) return this;
    final positions = _editablePositions(
      selectedPartIndex!,
    ).where((p) => p.measure == selectedMeasureIndex).toList();
    if (positions.isEmpty) return this;
    return _selectSpan(selectedPartIndex!, positions.first, positions.last);
  }

  /// The selected notes and rests, bar by bar; null without a selection.
  EditorClipboard? copySelection() {
    final positions = selectionPositions;
    if (positions.isEmpty) return null;
    final measures = score.parts[selectedPartIndex!].measures;
    final picked = positions.toSet();
    return EditorClipboard([
      for (var m = positions.first.measure; m <= positions.last.measure; m++)
        [
          for (final (i, symbol) in measures[m].symbols.indexed)
            if (picked.contains((measure: m, symbol: i)))
              // A copy starting inside a chord starts a new chord.
              _pasteCopy(
                symbol,
                startsChord: (measure: m, symbol: i) == positions.first,
              ),
        ],
    ]);
  }

  /// Removes every selected note and rest as one undo step, keeping the
  /// first bar as context.
  EditorState deleteSelection() {
    if (!hasRange) return deleteSelectedSymbol();
    final positions = selectionPositions;
    return applyEditWithMeasureContext(
      score: _repairEditedBeams(_without(positions)),
      partIndex: selectedPartIndex!,
      measureIndex: positions.first.measure,
    );
  }

  Score _without(List<SymbolPosition> positions) {
    var next = score;
    for (final p in positions.reversed) {
      next = next.deleteSymbolAt(selectedPartIndex!, p.measure, p.symbol);
    }
    return next;
  }

  /// Pastes [clipboard] bar by bar: over the range when there is one, else
  /// after the selection (or at the end of the selected bar); later bars
  /// start the following bars, which are added at the end of the score as
  /// needed. Returns this state unchanged when a bar would overflow. The
  /// pasted music is selected, as one undo step.
  EditorState paste(EditorClipboard clipboard) {
    if (!hasMeasureContext || clipboard.symbolCount == 0) return this;
    final part = selectedPartIndex!;
    final firstBar = hasRange
        ? selectionPositions.first.measure
        : selectedMeasureIndex!;
    var index = hasRange ? selectionPositions.first.symbol : _inputIndex;
    var next = hasRange ? _without(selectionPositions) : score;
    SymbolPosition? first, last;
    for (final (k, bar) in clipboard.bars.indexed) {
      final measure = firstBar + k;
      while (measure >= next.parts[part].measures.length) {
        next = next.insertMeasureAfterInAllParts(
          next.parts[part].measures.length - 1,
        );
      }
      if (k > 0) index = 0;
      for (final symbol in bar) {
        next = next.insertSymbolAt(part, measure, index, _pasteCopy(symbol));
        first ??= (measure: measure, symbol: index);
        last = (measure: measure, symbol: index);
        index++;
      }
      if (bar.isNotEmpty && !_fitsMeter(next, part, measure)) return this;
    }
    next = _repairEditedBeams(next);
    final pasted = applyEditWithSymbolSelection(
      score: next,
      partIndex: part,
      measureIndex: last!.measure,
      symbolIndex: last.symbol,
      symbol: next.getSymbolAt(part, last.measure, last.symbol)!,
    );
    return pasted.copyWith(rangeAnchor: first);
  }

  /// Transposes the selected notes only, keeping key signatures and the
  /// range; one undo step.
  EditorState transposeSelection(TransposeOptions options) {
    final positions = selectionPositions.toSet();
    if (positions.isEmpty) return this;
    final part = selectedPartIndex!;
    final anchor = rangeAnchor;
    return _applySelectionPreservingEdit(
      intent: EditorEditIntent.transpose,
      score: const Transposer().transpose(
        score,
        options,
        only: (p, m, s) =>
            p == part && positions.contains((measure: m, symbol: s)),
      ),
    ).copyWith(rangeAnchor: anchor);
  }

  // ── Ties and slurs ───────────────────────────────────────────────────

  /// The first note or rest after [from] in the same voice, in this or a
  /// later bar, skipping chord tones of the chord at [from].
  SymbolPosition? _nextInLane(SymbolPosition from) {
    final measures = score.parts[selectedPartIndex!].measures;
    final start = measures[from.measure].symbols[from.symbol];
    final lane = ScoreTimelineBuilder.lane(start);
    for (var m = from.measure; m < measures.length; m++) {
      for (final (i, symbol) in measures[m].symbols.indexed) {
        if (m == from.measure && i <= from.symbol) continue;
        if (symbol is Note && symbol.isChordTone) continue;
        if ((symbol is Note || symbol is Rest) &&
            ScoreTimelineBuilder.lane(symbol) == lane) {
          return (measure: m, symbol: i);
        }
      }
    }
    return null;
  }

  /// The note of the next chord in this voice with the selected note's
  /// staff position.
  Note? get _tieTarget {
    final note = selectedSymbol;
    if (!hasEditableSelection || note is! Note) return null;
    final next = _nextInLane((
      measure: selectedMeasureIndex!,
      symbol: selectedSymbolIndex!,
    ));
    if (next == null) return null;
    final symbols =
        score.parts[selectedPartIndex!].measures[next.measure].symbols;
    for (var i = next.symbol; i < symbols.length; i++) {
      final candidate = symbols[i];
      if (candidate is! Note || (i > next.symbol && !candidate.isChordTone)) {
        break;
      }
      if ((candidate.step, candidate.octave) == (note.step, note.octave)) {
        return candidate;
      }
    }
    return null;
  }

  Spanner? _spannerFrom(SpannerKind kind, String? from) =>
      score.spanners.where((s) => s.kind == kind && s.from == from).firstOrNull;

  /// Why the selection cannot be tied, or null.
  String? get tieUnavailableReason {
    final note = selectedSymbol;
    if (!hasEditableSelection || note is! Note) return 'Select a note';
    if (hasRange) return 'Select a single note';
    if (_spannerFrom(SpannerKind.tie, note.reviewId) != null) return null;
    return _tieTarget?.reviewId == null
        ? 'The next note in this voice is not the same pitch'
        : null;
  }

  /// Ties the selected note to the next note of the same pitch in its voice,
  /// or removes its tie (MuseScore's +).
  EditorState toggleTie() {
    if (tieUnavailableReason != null) return this;
    final id = (selectedSymbol as Note).reviewId!;
    final existing = _spannerFrom(SpannerKind.tie, id);
    return _withSpanners([
      for (final s in score.spanners)
        if (s != existing) s,
      if (existing == null) Spanner(SpannerKind.tie, id, _tieTarget!.reviewId!),
    ]);
  }

  /// The notes a slur would join: the first and last notes of a range, or
  /// the selected note and the next note in its voice.
  (Note, Note)? get _slurEnds {
    if (!hasEditableSelection) return null;
    final symbols = score.parts[selectedPartIndex!].measures;
    if (hasRange) {
      final notes = [
        for (final p in selectionPositions)
          if (symbols[p.measure].symbols[p.symbol] case final Note n
              when !n.isChordTone)
            n,
      ];
      return notes.length < 2 ? null : (notes.first, notes.last);
    }
    final note = selectedSymbol;
    if (note is! Note) return null;
    final next = _nextInLane((
      measure: selectedMeasureIndex!,
      symbol: selectedSymbolIndex!,
    ));
    if (next == null) return null;
    final target = symbols[next.measure].symbols[next.symbol];
    return target is Note ? (note, target) : null;
  }

  String? get slurUnavailableReason {
    final ends = _slurEnds;
    if (ends == null) {
      return hasRange
          ? 'Select at least two notes'
          : 'Select a note followed by another note in its voice';
    }
    return ends.$1.reviewId == null || ends.$2.reviewId == null
        ? 'Save or edit the score once, then try again'
        : null;
  }

  /// Slurs the selected range, or the selected note to the next note in its
  /// voice; the same slur again removes it (MuseScore's S).
  EditorState toggleSlur() {
    if (slurUnavailableReason != null) return this;
    final (from, to) = _slurEnds!;
    final slur = Spanner(SpannerKind.slur, from.reviewId!, to.reviewId!);
    return _withSpanners(
      score.spanners.contains(slur)
          ? [
              for (final s in score.spanners)
                if (s != slur) s,
            ]
          : [...score.spanners, slur],
    );
  }

  /// Note input's +: writes the selected note's pitch again in [spec],
  /// tied to it.
  EditorState enterTiedNote(DurationSpec spec) {
    final note = selectedSymbol;
    if (!hasEditableSelection || note is! Note || note.reviewId == null) {
      return this;
    }
    final tied = Note(
      step: note.step,
      octave: note.octave,
      alter: note.alter,
      duration: spec.divisions,
      type: spec.type,
      voice: note.voice,
      staff: note.staff,
      reviewId: NotationReviewService.newId(),
    );
    final next = _enterSymbol(tied);
    if (identical(next, this)) return this;
    return next.copyWith(
      score: next.score.copyWith(
        spanners: [
          ...next.score.spanners,
          Spanner(SpannerKind.tie, note.reviewId!, tied.reviewId!),
        ],
      ),
    );
  }

  EditorState _withSpanners(List<Spanner> spanners) =>
      _applySelectionPreservingEdit(
        intent: EditorEditIntent.updateMeasureMetadata,
        score: score.copyWith(spanners: spanners),
      ).copyWith(rangeAnchor: rangeAnchor);

  // ── Staves and instruments ───────────────────────────────────────────

  /// Why a staff cannot be added, or null. A scanned score's staves are
  /// lines of one part played in reading order; another instrument would
  /// play them all at once.
  String? get addStaffBlockedReason =>
      score.playbackLayout == ScorePlaybackLayout.sequentialStaves &&
          score.parts.length > 1
      ? 'These scanned staves are played one after another, as lines of one part. Adding an instrument would play them together.'
      : null;

  /// Rebuilds the parts from [plan] as one undo step: keeps, reorders,
  /// renames and removes parts, and adds empty ones whose bars copy the
  /// meter, key, breaks and barlines of the existing music. Adding a staff
  /// makes the parts play together.
  EditorState rearrangeParts(List<StaffPlanEntry> plan) {
    if (plan.isEmpty || score.parts.isEmpty) return this;
    final adds = plan.any((e) => e.from == null);
    if (adds && addStaffBlockedReason != null) return this;
    final template =
        score.parts[plan.map((e) => e.from).nonNulls.firstOrNull ?? 0];
    final ids = {for (final p in score.parts) p.id};
    String newId() {
      var k = score.parts.length + 1;
      while (ids.contains('P$k')) {
        k++;
      }
      ids.add('P$k');
      return 'P$k';
    }

    // A staff joins the one above only while it still follows the staff it
    // joined (or, when new, another new staff).
    int staffOf(int i) {
      final entry = plan[i];
      if (!entry.joinsPrevious || i == 0) return 1;
      final above = plan[i - 1];
      final adjacent = entry.from == null
          ? above.from == null
          : above.from == entry.from! - 1;
      return adjacent ? staffOf(i - 1) + 1 : 1;
    }

    final parts = [
      for (final (i, entry) in plan.indexed)
        if (entry.from case final from?)
          Part(
            id: score.parts[from].id,
            name: entry.name,
            staff: staffOf(i),
            measures: score.parts[from].measures,
          )
        else
          Part(
            id: newId(),
            name: entry.name,
            staff: staffOf(i),
            measures: [
              for (final (i, m) in template.measures.indexed)
                Measure(
                  number: m.number,
                  clef: i == 0
                      ? entry.clef ?? const Clef(sign: 'G', line: 2)
                      : null,
                  timeSignature: m.timeSignature,
                  keySignature: m.keySignature,
                  symbols: const [],
                  startsNewPage: m.startsNewPage,
                  startsNewSystem: m.startsNewSystem,
                  leftBarlineType: m.leftBarlineType,
                  rightBarlineType: m.rightBarlineType,
                ),
            ],
          ),
    ];
    final next = score.copyWith(
      parts: parts,
      playbackLayout: adds ? ScorePlaybackLayout.simultaneousParts : null,
    );
    final kept = plan.indexWhere((e) => e.from == selectedPartIndex);
    if (kept >= 0 && hasSymbolSelection) {
      return applyEditWithSymbolSelection(
        score: next,
        partIndex: kept,
        measureIndex: selectedMeasureIndex!,
        symbolIndex: selectedSymbolIndex!,
        symbol: selectedSymbol!,
      );
    }
    return applyEditWithMeasureContext(
      score: next,
      partIndex: kept >= 0 ? kept : 0,
      measureIndex: kept >= 0 ? (selectedMeasureIndex ?? 0) : 0,
    );
  }

  /// Transposes every part as one undo step, keeping the selection.
  EditorState transposeScore(TransposeOptions options) =>
      _applySelectionPreservingEdit(
        intent: EditorEditIntent.transpose,
        score: const Transposer().transpose(score, options),
      );

  // ── Keyboard note input (MuseScore-style) ────────────────────────────

  /// After the selected symbol and any chord tones that follow it, else at
  /// the end of the selected bar.
  int get _inputIndex {
    final symbols =
        score.parts[selectedPartIndex!].measures[selectedMeasureIndex!].symbols;
    if (!hasEditableSelection) return symbols.length;
    var index = selectedSymbolIndex! + 1;
    while (index < symbols.length &&
        symbols[index] is Note &&
        (symbols[index] as Note).isChordTone) {
      index++;
    }
    return index;
  }

  /// Writes [step] (C–B) as a new note of [spec] after the input position,
  /// in the octave nearest the previous note. A full bar continues at the
  /// start of the next one, adding a bar at the end of the score if needed.
  ///
  /// [voice] (1–4) writes into that voice; otherwise input continues the
  /// selected symbol's voice. See [_enterSymbol] for changing voice.
  EditorState enterNote(String step, DurationSpec spec, {int? voice}) {
    if (!hasMeasureContext || !_stepNames.contains(step)) return this;
    final (voice: inputVoice, :staff) = _inputLaneFor(voice);
    final pitch = _nearestDiatonic(step, _inputReference);
    return _enterSymbol(
      Note(
        step: _stepNames[pitch % 7],
        octave: pitch ~/ 7,
        duration: spec.divisions,
        type: spec.type,
        voice: inputVoice,
        staff: staff,
      ),
    );
  }

  /// Writes a rest of [spec] at the input position, as [enterNote] does.
  EditorState enterRest(DurationSpec spec, {int? voice}) {
    if (!hasMeasureContext) return this;
    final (voice: inputVoice, :staff) = _inputLaneFor(voice);
    return _enterSymbol(
      Rest(
        duration: spec.divisions,
        type: spec.type,
        voice: inputVoice,
        staff: staff,
      ),
    );
  }

  /// The voice and staff new input goes to: [voice] when given (voice 1 is
  /// left unwritten when the selection's voice is unwritten), else the
  /// selection's.
  ({int? voice, int? staff}) _inputLaneFor(int? voice) {
    final (selectedVoice, staff) = _inputLane;
    if (voice == null || voice == (selectedVoice ?? 1)) {
      return (voice: selectedVoice, staff: staff);
    }
    return (voice: voice == 1 ? null : voice, staff: staff);
  }

  /// Re-pitches the selected note to [step] in the octave nearest its
  /// current pitch; the key signature decides the accidental.
  EditorState setSelectedNoteStep(String step) {
    final note = selectedSymbol;
    if (!hasEditableSelection || note is! Note || !_stepNames.contains(step)) {
      return this;
    }
    final pitch = _nearestDiatonic(step, _diatonic(note));
    if (pitch == _diatonic(note) && note.alter == null) return this;
    return _replaceSelectedSymbol(
      _pitched(note, pitch, alter: null),
      intent: EditorEditIntent.replaceSelection,
    );
  }

  bool get canAddChordTone => hasEditableSelection && selectedSymbol is Note;

  /// Adds a chord tone a diatonic [interval] above the selected note (3 is a
  /// third) and selects it, so repeating the command stacks intervals.
  EditorState addChordInterval(int interval) {
    final note = selectedSymbol;
    if (!canAddChordTone || note is! Note || interval < 2) return this;
    return _addChordTone(_diatonic(note) + interval - 1);
  }

  /// Adds [step] to the selected note's chord, in the nearest octave above
  /// the selected note.
  EditorState addChordStep(String step) {
    final note = selectedSymbol;
    if (!canAddChordTone || note is! Note || !_stepNames.contains(step)) {
      return this;
    }
    var pitch = (note.octave * 7) + _stepNames.indexOf(step);
    while (pitch <= _diatonic(note)) {
      pitch += 7;
    }
    return _addChordTone(pitch);
  }

  EditorState _addChordTone(int pitch) {
    if (pitch > _maxDiatonic) return this;
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbols = score.parts[partIndex].measures[measureIndex].symbols;
    var baseIndex = selectedSymbolIndex!;
    while (baseIndex > 0 &&
        symbols[baseIndex] is Note &&
        (symbols[baseIndex] as Note).isChordTone) {
      baseIndex--;
    }
    final base = symbols[baseIndex];
    if (base is! Note) return this;
    final end = _inputIndex;
    for (final tone in symbols.sublist(baseIndex, end)) {
      if (tone is Note && _diatonic(tone) == pitch) return this;
    }
    final tone = Note(
      step: _stepNames[pitch % 7],
      octave: pitch ~/ 7,
      duration: base.duration,
      type: base.type,
      dots: base.dots,
      voice: base.voice,
      staff: base.staff,
      isChordTone: true,
      tuplet: base.tuplet,
    );
    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.insertAfterSelection,
      score: score.insertSymbolAt(partIndex, measureIndex, end, tone),
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: end,
      symbol: tone,
    );
  }

  /// New input continues the selected symbol's voice and staff.
  (int?, int?) get _inputLane => switch (selectedEditableSymbol) {
    Note(:final voice, :final staff) ||
    Rest(:final voice, :final staff) => (voice, staff),
    _ => (null, null),
  };

  /// The pitch the next letter is measured from: the selected note, else the
  /// closest note before the input position in this part, else the middle
  /// line of the active clef.
  int get _inputReference {
    if (selectedEditableSymbol case final Note note) return _diatonic(note);
    final partIndex = selectedPartIndex!;
    final measures = score.parts[partIndex].measures;
    for (var m = selectedMeasureIndex!; m >= 0; m--) {
      final symbols = measures[m].symbols;
      final from = m == selectedMeasureIndex! ? _inputIndex : symbols.length;
      for (var i = from - 1; i >= 0; i--) {
        final symbol = symbols[i];
        if (symbol is Note) {
          return _diatonic(symbol);
        }
      }
    }
    final clef =
        [
          for (var m = selectedMeasureIndex!; m >= 0; m--) measures[m].clef,
        ].nonNulls.firstOrNull ??
        const Clef(sign: 'G', line: 2);
    final signPitch = switch (clef.sign) {
      'F' => 24, // F3
      'C' => 28, // C4
      _ => 32, // G4
    };
    return signPitch + (3 - clef.line) * 2;
  }

  /// Inserts [symbol] at the input position. In a different voice from the
  /// selection it starts where the selected symbol starts, as in MuseScore:
  /// rests fill that voice up to there, and the symbol goes at the end of
  /// the bar's list (each voice keeps its own time).
  EditorState _enterSymbol(ScoreSymbol symbol) {
    final partIndex = selectedPartIndex!;
    var measureIndex = selectedMeasureIndex!;
    final lane = ScoreTimelineBuilder.lane(symbol);
    final selected = selectedEditableSymbol;
    var items = [symbol];
    var index = _inputIndex;
    if (selected != null && ScoreTimelineBuilder.lane(selected) != lane) {
      try {
        final timeline = const ScoreTimelineBuilder().measure(
          score,
          partIndex,
          measureIndex,
        );
        final start = timeline.symbols
            .firstWhere((e) => e.symbolIndex == selectedSymbolIndex)
            .onset;
        final gap = (start - timeline.laneDuration(lane)).asDouble;
        final (voice, staff) = switch (symbol) {
          Note(:final voice, :final staff) ||
          Rest(:final voice, :final staff) => (voice, staff),
          _ => (null, null),
        };
        items = [..._restsFilling(gap, voice: voice, staff: staff), symbol];
      } on ScoreTimelineException {
        return this;
      }
      index = score.parts[partIndex].measures[measureIndex].symbols.length;
    }
    var next = _insertAll(score, partIndex, measureIndex, index, items);
    if (!_laneFits(next, partIndex, measureIndex, lane)) {
      // Continue at the start of the next bar.
      measureIndex++;
      index = 0;
      items = [symbol];
      next = score;
      if (measureIndex == score.parts[partIndex].measures.length) {
        next = next.insertMeasureAfterInAllParts(measureIndex - 1);
      }
      next = _insertAll(next, partIndex, measureIndex, index, items);
      if (!_laneFits(next, partIndex, measureIndex, lane)) return this;
    }
    final symbolIndex = index + items.length - 1;
    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.insertAfterSelection,
      score: next,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: symbolIndex,
      symbol: symbol,
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
      note.copyWith(alter: alter, beamed: note.beamed, confidence: null),
      intent: EditorEditIntent.replaceSelection,
    );
  }

  EditorState moveSelectedSymbolToMeasureOffset(int offset) {
    if (!hasEditableSelection || offset == 0) return this;

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
    if (!_canMeasureAcceptSymbol(
      partIndex: partIndex,
      measureIndex: toMeasureIndex,
      symbol: moved,
    )) {
      return this;
    }
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

    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.moveSelectionAcrossMeasures,
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
      return _applySymbolSelectionEdit(
        intent: EditorEditIntent.reorderWithinMeasure,
        score: nextScore,
        partIndex: fromPartIndex,
        measureIndex: fromMeasureIndex,
        symbolIndex: clampedTo,
        symbol: symbols[clampedTo],
      );
    }

    // Cross-measure move: delete from source, insert at destination.
    final moved = fromMeasures[fromMeasureIndex].symbols[fromSymbolIndex];
    if (!_canMeasureAcceptSymbol(
      partIndex: toPartIndex,
      measureIndex: toMeasureIndex,
      symbol: moved,
    )) {
      return this;
    }
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

    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.moveSelectionAcrossMeasures,
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
      return _applySelectionPreservingEdit(
        intent: EditorEditIntent.reorderWithinMeasure,
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

    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.reorderWithinMeasure,
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: nextSelectedIndex,
      symbol: symbols[nextSelectedIndex],
    );
  }

  EditorState _replaceSelectedSymbol(
    ScoreSymbol symbol, {
    required EditorEditIntent intent,
  }) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final symbolIndex = selectedSymbolIndex!;

    final nextScore = score.replaceSymbolAt(
      partIndex,
      measureIndex,
      symbolIndex,
      symbol,
    );

    return _applySymbolSelectionEdit(
      intent: intent,
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
    if (insertIndex < 0 ||
        insertIndex > measures[measureIndex].symbols.length) {
      return this;
    }
    if (!_canMeasureAcceptSymbol(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbol: symbol,
    )) {
      return this;
    }

    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return _applySymbolSelectionEdit(
      intent: EditorEditIntent.insertAtTarget,
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: insertIndex,
      symbol: symbol,
    );
  }

  EditorState _insertAfterSelectionOrAppend(
    ScoreSymbol symbol, {
    required EditorEditIntent intent,
  }) {
    final partIndex = selectedPartIndex!;
    final measureIndex = selectedMeasureIndex!;
    final insertIndex = _inputIndex;
    if (!_canMeasureAcceptSymbol(
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbol: symbol,
    )) {
      return this;
    }

    final nextScore = score.insertSymbolAt(
      partIndex,
      measureIndex,
      insertIndex,
      symbol,
    );

    return _applySymbolSelectionEdit(
      intent: intent,
      score: nextScore,
      partIndex: partIndex,
      measureIndex: measureIndex,
      symbolIndex: insertIndex,
      symbol: symbol,
    );
  }

  EditorState _applyMeasureContextEdit({
    required EditorEditIntent intent,
    required Score score,
    required int partIndex,
    required int measureIndex,
  }) {
    final next = intent == EditorEditIntent.deleteSelection
        ? _repairEditedBeams(score)
        : score;
    switch (intent) {
      case EditorEditIntent.deleteMeasure:
      case EditorEditIntent.createMeasure:
      case EditorEditIntent.createPage:
      case EditorEditIntent.deleteSelection:
        return applyEditWithMeasureContext(
          score: next,
          partIndex: partIndex,
          measureIndex: measureIndex,
        );
      default:
        throw ArgumentError.value(
          intent,
          'intent',
          'Intent does not preserve only measure context.',
        );
    }
  }

  EditorState _applySymbolSelectionEdit({
    required EditorEditIntent intent,
    required Score score,
    required int partIndex,
    required int measureIndex,
    required int symbolIndex,
    required ScoreSymbol symbol,
  }) {
    final changedValue =
        (selectedSymbol is Note) != (symbol is Note) ||
        (selectedSymbol is Note &&
            symbol is Note &&
            BeamGrouping.levels(selectedSymbol as Note) !=
                BeamGrouping.levels(symbol));
    final next = intent != EditorEditIntent.replaceSelection || changedValue
        ? _repairEditedBeams(score)
        : score;
    switch (intent) {
      case EditorEditIntent.replaceSelection:
      case EditorEditIntent.appendToMeasure:
      case EditorEditIntent.insertAfterSelection:
      case EditorEditIntent.insertAtTarget:
      case EditorEditIntent.moveSelectionAcrossMeasures:
      case EditorEditIntent.reorderWithinMeasure:
      case EditorEditIntent.deleteSelection:
        return applyEditWithSymbolSelection(
          score: next,
          partIndex: partIndex,
          measureIndex: measureIndex,
          symbolIndex: symbolIndex,
          symbol:
              next.getSymbolAt(partIndex, measureIndex, symbolIndex) ?? symbol,
        );
      default:
        throw ArgumentError.value(
          intent,
          'intent',
          'Intent does not preserve symbol selection.',
        );
    }
  }

  EditorState _applySelectionPreservingEdit({
    required EditorEditIntent intent,
    required Score score,
  }) {
    final next = intent == EditorEditIntent.reorderWithinMeasure
        ? _repairEditedBeams(score)
        : score;
    switch (intent) {
      case EditorEditIntent.updateMeasureMetadata:
      case EditorEditIntent.reorderWithinMeasure:
      case EditorEditIntent.transpose:
        return applyEdit(
          score: next,
          selectedPartIndex: selectedPartIndex,
          selectedMeasureIndex: selectedMeasureIndex,
          selectedSymbolIndex: selectedSymbolIndex,
          selectedSymbol: hasSymbolSelection
              ? next.getSymbolAt(
                  selectedPartIndex!,
                  selectedMeasureIndex!,
                  selectedSymbolIndex!,
                )
              : null,
        );
      default:
        throw ArgumentError.value(
          intent,
          'intent',
          'Intent does not preserve existing selection.',
        );
    }
  }

  Score _repairEditedBeams(Score candidate) {
    var next = candidate;
    for (var p = 0; p < candidate.parts.length; p++) {
      for (var m = 0; m < candidate.parts[p].measures.length; m++) {
        final symbols = candidate.parts[p].measures[m].symbols;
        final oldSymbols =
            p < score.parts.length && m < score.parts[p].measures.length
            ? score.parts[p].measures[m].symbols
            : null;
        if (identical(symbols, oldSymbols)) continue;
        final repaired = BeamGrouping.repairExplicit(symbols);
        if (identical(repaired, symbols)) continue;
        for (var i = 0; i < symbols.length; i++) {
          if (!identical(symbols[i], repaired[i])) {
            next = next.replaceSymbolAt(p, m, i, repaired[i]);
          }
        }
      }
    }
    return next;
  }

  bool _canReplaceSelectedSymbolWith(double nextQuarters) {
    if (!hasEditableSelection) return false;
    try {
      final timeline = const ScoreTimelineBuilder().measure(
        score,
        selectedPartIndex!,
        selectedMeasureIndex!,
        writtenOverrides: {
          selectedSymbolIndex!: MusicalTime.decimal('$nextQuarters'),
        },
      );
      final selected = timeline.symbols
          .where((e) => e.symbolIndex == selectedSymbolIndex)
          .firstOrNull;
      if (selected == null) return false;
      final capacity = ScoreTimelineBuilder.meterLength(
        _activeTimeSignatureForMeasure(
          partIndex: selectedPartIndex!,
          measureIndex: selectedMeasureIndex!,
        ),
      );
      return capacity.isZero ||
          timeline.laneDuration(selected.lane).compareTo(capacity) <= 0;
    } on ScoreTimelineException {
      return false;
    }
  }

  bool _canMeasureAcceptSymbol({
    required int partIndex,
    required int measureIndex,
    required ScoreSymbol symbol,
  }) {
    if (symbol is! Note && symbol is! Rest) return true;
    final symbols = score.parts[partIndex].measures[measureIndex].symbols;
    try {
      final timeline = const ScoreTimelineBuilder().measure(
        score,
        partIndex,
        measureIndex,
        symbols: [...symbols, symbol],
      );
      final inserted = timeline.symbols
          .where((e) => e.symbolIndex == symbols.length)
          .firstOrNull;
      if (inserted == null) return false;
      final capacity = ScoreTimelineBuilder.meterLength(
        _activeTimeSignatureForMeasure(
          partIndex: partIndex,
          measureIndex: measureIndex,
        ),
      );
      return capacity.isZero ||
          timeline.laneDuration(inserted.lane).compareTo(capacity) <= 0;
    } on ScoreTimelineException {
      return false;
    }
  }

  TimeSignature? _activeTimeSignatureForMeasure({
    required int partIndex,
    required int measureIndex,
  }) {
    final measures = score.parts[partIndex].measures;
    for (var i = measureIndex; i >= 0; i--) {
      final timeSignature = measures[i].timeSignature;
      if (timeSignature != null) {
        return timeSignature;
      }
    }

    return null;
  }
}

const _stepNames = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

/// A pasted copy: no scan evidence or review identity of its own.
ScoreSymbol _pasteCopy(ScoreSymbol symbol, {bool startsChord = false}) =>
    switch (symbol) {
      Note() => symbol.copyWith(
        beams: symbol.beams,
        isChordTone: symbol.isChordTone && !startsChord,
        confidence: null,
        reviewId: null,
        source: null,
      ),
      Rest() => symbol.copyWith(confidence: null, reviewId: null, source: null),
      _ => symbol,
    };

Score _insertAll(
  Score score,
  int part,
  int measure,
  int index,
  List<ScoreSymbol> symbols,
) {
  for (final (k, symbol) in symbols.indexed) {
    score = score.insertSymbolAt(part, measure, index + k, symbol);
  }
  return score;
}

/// Whether [lane] in [measure] fits its time signature.
bool _laneFits(Score score, int part, int measure, VoiceLane lane) {
  try {
    final timeline = const ScoreTimelineBuilder().measure(score, part, measure);
    final capacity = ScoreTimelineBuilder.meterLength(
      ScoreTimelineBuilder.activeMeter(score, part, measure),
    );
    return capacity.isZero ||
        timeline.laneDuration(lane).compareTo(capacity) <= 0;
  } on ScoreTimelineException {
    return false;
  }
}

/// Rests that fill [quarters] (largest first, dotted values allowed).
List<Rest> _restsFilling(double quarters, {int? voice, int? staff}) {
  const values = [
    (4.0, 'whole', 0),
    (3.0, 'half', 1),
    (2.0, 'half', 0),
    (1.5, 'quarter', 1),
    (1.0, 'quarter', 0),
    (0.75, 'eighth', 1),
    (0.5, 'eighth', 0),
    (0.25, 'sixteenth', 0),
  ];
  final rests = <Rest>[];
  var left = quarters;
  for (final (length, type, dots) in values) {
    while (left >= length - 1e-9) {
      rests.add(
        Rest(
          duration: math.max(1, (length * 2).round()),
          type: type,
          dots: dots,
          voice: voice,
          staff: staff,
        ),
      );
      left -= length;
    }
  }
  return rests;
}

/// Whether every voice in [measure] fits its time signature.
bool _fitsMeter(Score score, int part, int measure) {
  try {
    final timeline = const ScoreTimelineBuilder().measure(score, part, measure);
    final capacity = ScoreTimelineBuilder.meterLength(
      ScoreTimelineBuilder.activeMeter(score, part, measure),
    );
    return capacity.isZero ||
        timeline.symbols.every(
          (e) => timeline.laneDuration(e.lane).compareTo(capacity) <= 0,
        );
  } on ScoreTimelineException {
    return false;
  }
}

/// Octaves 1–7, the range the editor shows.
const _minDiatonic = 7, _maxDiatonic = 7 * 7 + 6;

/// Staff position counted in diatonic steps from C0.
int _diatonic(Note note) => note.octave * 7 + _stepNames.indexOf(note.step);

/// [step] within a fourth of [reference], kept inside the editor's range.
int _nearestDiatonic(String step, int reference) {
  var pitch = (reference ~/ 7) * 7 + _stepNames.indexOf(step);
  if (pitch - reference > 3) pitch -= 7;
  if (reference - pitch > 3) pitch += 7;
  if (pitch < _minDiatonic) pitch += 7;
  if (pitch > _maxDiatonic) pitch -= 7;
  return pitch;
}

Note _pitched(
  Note note,
  int pitch, {
  required int? alter,
  bool? isChordTone,
  Map<int, BeamValue>? beams,
}) => note.copyWith(
  step: _stepNames[pitch % 7],
  octave: pitch ~/ 7,
  alter: alter,
  beamed: note.beamed,
  beams: beams ?? note.beams,
  isChordTone: isChordTone ?? note.isChordTone,
);

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

  // Past the range the editor shows, the note stays where it is.
  if (nextOctave < 1 || nextOctave > 7) return note;

  return note.copyWith(
    step: stepsByName[nextIndex],
    octave: nextOctave,
    beamed: note.beamed,
    confidence: null,
  );
}
