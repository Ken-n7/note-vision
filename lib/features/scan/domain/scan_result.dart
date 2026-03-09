import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class ScanResult {
  final PreprocessedResult preprocessed;
  final List<DetectedSymbol> symbols;

  const ScanResult({
    required this.preprocessed,
    required this.symbols,
  });

  bool get hasDetections => symbols.isNotEmpty;
}