import 'dart:typed_data';
import 'preprocessed_result.dart';

abstract class ImagePreprocessor {
  Future<PreprocessedResult> preprocess(Uint8List bytes);
}