import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class ScanResult {
  final PreprocessedResult preprocessed;
  final DetectionResult detection;

  const ScanResult({required this.preprocessed, required this.detection});

  List<DetectedSymbol> get symbols => detection.symbols;

  bool get hasDetections => detection.hasDetections;
}
