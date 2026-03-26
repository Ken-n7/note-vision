import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/resolution/domain/resolved_score.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

class ScanResult {
  final PreprocessedResult preprocessed;
  final DetectionResult detection;
  final ScoreStructure? structure;
  final ResolvedScore? resolvedScore;

  const ScanResult({
    required this.preprocessed,
    required this.detection,
    this.structure,
    this.resolvedScore,
  });

  List<DetectedSymbol> get symbols => resolvedScore?.symbols ?? detection.symbols;

  bool get hasDetections => detection.hasDetections;
}
