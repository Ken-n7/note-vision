import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';

class EditorSnapshot {
  const EditorSnapshot({
    required this.score,
    required this.selectedPartIndex,
    required this.selectedMeasureIndex,
    required this.selectedSymbolIndex,
    required this.selectedSymbol,
    required this.hasUnsavedChanges,
  });

  final Score score;
  final int? selectedPartIndex;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  final ScoreSymbol? selectedSymbol;
  final bool hasUnsavedChanges;
}
