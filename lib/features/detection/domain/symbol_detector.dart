import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'detection_result.dart';

abstract class SymbolDetector {
  Future<DetectionResult> detect(PreprocessedResult input);
}