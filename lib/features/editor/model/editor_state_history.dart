import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/editor/model/editor_snapshot.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

extension EditorStateHistory on EditorState {
  EditorState applyEdit({
    required Score score,
    int? selectedPartIndex,
    int? selectedMeasureIndex,
    int? selectedSymbolIndex,
    ScoreSymbol? selectedSymbol,
    bool clearSelection = false,
  }) {
    final updatedUndoStack = _pushWithLimit(undoStack, toSnapshot());
    return copyWith(
      score: score,
      selectedPartIndex: selectedPartIndex,
      selectedMeasureIndex: selectedMeasureIndex,
      selectedSymbolIndex: selectedSymbolIndex,
      selectedSymbol: selectedSymbol,
      clearSelection: clearSelection,
      undoStack: updatedUndoStack,
      redoStack: const [],
      hasUnsavedChanges: true,
    );
  }

  EditorState undo() {
    if (undoStack.isEmpty) return this;

    final previousSnapshot = undoStack.last;
    final remainingUndoStack = List<EditorSnapshot>.from(undoStack)
      ..removeLast();
    final updatedRedoStack = _pushWithLimit(redoStack, toSnapshot());

    return _restoreSnapshot(
      snapshot: previousSnapshot,
      undoStack: remainingUndoStack,
      redoStack: updatedRedoStack,
    );
  }

  EditorState redo() {
    if (redoStack.isEmpty) return this;

    final nextSnapshot = redoStack.last;
    final remainingRedoStack = List<EditorSnapshot>.from(redoStack)
      ..removeLast();
    final updatedUndoStack = _pushWithLimit(undoStack, toSnapshot());

    return _restoreSnapshot(
      snapshot: nextSnapshot,
      undoStack: updatedUndoStack,
      redoStack: remainingRedoStack,
    );
  }

  EditorSnapshot toSnapshot() => EditorSnapshot(
    score: score,
    selectedPartIndex: selectedPartIndex,
    selectedMeasureIndex: selectedMeasureIndex,
    selectedSymbolIndex: selectedSymbolIndex,
    selectedSymbol: selectedSymbol,
    hasUnsavedChanges: hasUnsavedChanges,
  );
}

EditorState _restoreSnapshot({
  required EditorSnapshot snapshot,
  required List<EditorSnapshot> undoStack,
  required List<EditorSnapshot> redoStack,
}) {
  return EditorState(
    score: snapshot.score,
    selectedPartIndex: snapshot.selectedPartIndex,
    selectedMeasureIndex: snapshot.selectedMeasureIndex,
    selectedSymbolIndex: snapshot.selectedSymbolIndex,
    selectedSymbol: snapshot.selectedSymbol,
    undoStack: undoStack,
    redoStack: redoStack,
    hasUnsavedChanges: snapshot.hasUnsavedChanges,
  );
}

List<EditorSnapshot> _pushWithLimit(
  List<EditorSnapshot> stack,
  EditorSnapshot snapshot,
) {
  final next = List<EditorSnapshot>.from(stack)..add(snapshot);
  if (next.length <= EditorState.maxHistoryDepth) {
    return next;
  }
  return List<EditorSnapshot>.from(
    next.sublist(next.length - EditorState.maxHistoryDepth),
  );
}
