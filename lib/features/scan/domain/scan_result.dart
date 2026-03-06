import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';

class ScanResult {
  final PreprocessedResult preprocessed;
  // final List<DetectedSymbol> symbols; // uncomment when detection is ready

  const ScanResult({
    required this.preprocessed,
  });
}