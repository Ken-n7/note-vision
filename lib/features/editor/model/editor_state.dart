import 'dart:collection';

import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/editor/model/editor_snapshot.dart';

class EditorState {
  static const int maxHistoryDepth = 50;
  static const Object _unset = Object();

  final Score score;
  final int? selectedPartIndex;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  final ScoreSymbol? selectedSymbol;
  final List<EditorSnapshot> undoStack;
  final List<EditorSnapshot> redoStack;
  final bool hasUnsavedChanges;

  factory EditorState({
    required Score score,
    int? selectedPartIndex,
    int? selectedMeasureIndex,
    int? selectedSymbolIndex,
    ScoreSymbol? selectedSymbol,
    List<EditorSnapshot>? undoStack,
    List<EditorSnapshot>? redoStack,
    bool hasUnsavedChanges = false,
  }) {
    final normalizedSelection = _normalizeSelection(
      score: score,
      candidate: _Selection(
        partIndex: selectedPartIndex,
        measureIndex: selectedMeasureIndex,
        symbolIndex: selectedSymbolIndex,
        symbol: selectedSymbol,
      ),
    );

    return EditorState._(
      score: score,
      selectedPartIndex: normalizedSelection.partIndex,
      selectedMeasureIndex: normalizedSelection.measureIndex,
      selectedSymbolIndex: normalizedSelection.symbolIndex,
      selectedSymbol: normalizedSelection.symbol,
      undoStack: undoStack,
      redoStack: redoStack,
      hasUnsavedChanges: hasUnsavedChanges,
    );
  }

  EditorState._({
    required this.score,
    required this.selectedPartIndex,
    required this.selectedMeasureIndex,
    required this.selectedSymbolIndex,
    required this.selectedSymbol,
    List<EditorSnapshot>? undoStack,
    List<EditorSnapshot>? redoStack,
    required this.hasUnsavedChanges,
  }) : undoStack = UnmodifiableListView(_trimStack(undoStack ?? const [])),
       redoStack = UnmodifiableListView(_trimStack(redoStack ?? const [])) {
    _validateSelectedSymbolType(selectedSymbol);
  }

  EditorState copyWith({
    Score? score,
    Object? selectedPartIndex = _unset,
    Object? selectedMeasureIndex = _unset,
    Object? selectedSymbolIndex = _unset,
    Object? selectedSymbol = _unset,
    bool clearSelection = false,
    List<EditorSnapshot>? undoStack,
    List<EditorSnapshot>? redoStack,
    bool? hasUnsavedChanges,
  }) {
    final nextScore = score ?? this.score;

    final candidateSelection = clearSelection
        ? _Selection.none()
        : _Selection(
            partIndex: selectedPartIndex == _unset
                ? this.selectedPartIndex
                : selectedPartIndex as int?,
            measureIndex: selectedMeasureIndex == _unset
                ? this.selectedMeasureIndex
                : selectedMeasureIndex as int?,
            symbolIndex: selectedSymbolIndex == _unset
                ? this.selectedSymbolIndex
                : selectedSymbolIndex as int?,
            symbol: selectedSymbol == _unset
                ? this.selectedSymbol
                : selectedSymbol as ScoreSymbol?,
          );

    final normalizedSelection = _normalizeSelection(
      score: nextScore,
      candidate: candidateSelection,
    );

    return EditorState(
      score: nextScore,
      selectedPartIndex: normalizedSelection.partIndex,
      selectedMeasureIndex: normalizedSelection.measureIndex,
      selectedSymbolIndex: normalizedSelection.symbolIndex,
      selectedSymbol: normalizedSelection.symbol,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  bool get hasMeasureContext =>
      selectedPartIndex != null && selectedMeasureIndex != null;

  static List<EditorSnapshot> _trimStack(List<EditorSnapshot> stack) {
    if (stack.length <= maxHistoryDepth) {
      return List<EditorSnapshot>.from(stack);
    }
    return List<EditorSnapshot>.from(
      stack.sublist(stack.length - maxHistoryDepth),
    );
  }

  static _Selection _normalizeSelection({
    required Score score,
    required _Selection candidate,
  }) {
    final allNull =
        candidate.partIndex == null &&
        candidate.measureIndex == null &&
        candidate.symbolIndex == null &&
        candidate.symbol == null;

    if (allNull) return _Selection.none();

    if (candidate.partIndex == null || candidate.measureIndex == null) {
      return _Selection.none();
    }

    final partIndex = candidate.partIndex!;
    final measureIndex = candidate.measureIndex!;

    if (partIndex < 0 || partIndex >= score.parts.length) {
      return _Selection.none();
    }

    final part = score.parts[partIndex];
    if (measureIndex < 0 || measureIndex >= part.measures.length) {
      return _Selection.none();
    }

    final hasSymbolSelection =
        candidate.symbolIndex != null || candidate.symbol != null;
    if (!hasSymbolSelection) {
      return _Selection(
        partIndex: partIndex,
        measureIndex: measureIndex,
        symbolIndex: null,
        symbol: null,
      );
    }

    if (candidate.symbolIndex == null || candidate.symbol == null) {
      return _Selection.none();
    }

    _validateSelectedSymbolType(candidate.symbol);

    final symbolIndex = candidate.symbolIndex!;
    final measure = part.measures[measureIndex];
    if (symbolIndex < 0 || symbolIndex >= measure.symbols.length) {
      return _Selection.none();
    }

    final symbolAtIndex = measure.symbols[symbolIndex];
    if (!identical(symbolAtIndex, candidate.symbol)) {
      return _Selection.none();
    }

    return candidate;
  }

  static void _validateSelectedSymbolType(ScoreSymbol? symbol) {
    if (symbol == null) return;
    if (symbol is! Note && symbol is! Rest) {
      throw ArgumentError(
        'selectedSymbol must be either a Note or a Rest.',
      );
    }
  }

  @override
  String toString() {
    return 'EditorState('
        'scoreId: ${score.id}, '
        'selectedPartIndex: $selectedPartIndex, '
        'selectedMeasureIndex: $selectedMeasureIndex, '
        'selectedSymbolIndex: $selectedSymbolIndex, '
        'selectedSymbol: $selectedSymbol, '
        'undoDepth: ${undoStack.length}, '
        'redoDepth: ${redoStack.length}, '
        'hasUnsavedChanges: $hasUnsavedChanges'
        ')';
  }
}

class _Selection {
  const _Selection({
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
    required this.symbol,
  });

  const _Selection.none()
    : partIndex = null,
      measureIndex = null,
      symbolIndex = null,
      symbol = null;

  final int? partIndex;
  final int? measureIndex;
  final int? symbolIndex;
  final ScoreSymbol? symbol;
}
