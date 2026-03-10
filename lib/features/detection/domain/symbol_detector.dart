import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'detected_symbol.dart';

abstract class SymbolDetector {
  Future<List<DetectedSymbol>> detect(PreprocessedResult input);
}