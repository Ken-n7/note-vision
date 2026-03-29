import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../preprocessing/domain/image_preprocessor.dart';
import '../../preprocessing/domain/preprocessed_result.dart';

/// DEV-only preprocessor that mirrors a common YOLO export expectation:
/// - auto orientation
/// - direct stretch resize to 416x416
/// - keep RGB channels
class YoloParityImagePreprocessor implements ImagePreprocessor {
  const YoloParityImagePreprocessor();

  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) {
    return compute(_processYoloParity, bytes);
  }
}

PreprocessedResult _processYoloParity(Uint8List bytes) {
  const targetSize = 416;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format.');
  }

  final oriented = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    oriented,
    width: targetSize,
    height: targetSize,
    interpolation: img.Interpolation.linear,
  );

  return PreprocessedResult(
    bytes: Uint8List.fromList(img.encodePng(resized)),
    width: resized.width,
    height: resized.height,
    scale: targetSize / oriented.width,
    padX: 0,
    padY: 0,
  );
}
