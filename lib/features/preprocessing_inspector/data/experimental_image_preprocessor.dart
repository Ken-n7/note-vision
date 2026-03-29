import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../preprocessing/domain/image_preprocessor.dart';
import '../../preprocessing/domain/preprocessed_result.dart';

/// Experimental preprocessor for DEV inspection only.
///
/// This implementation is intentionally separate from the production
/// [BasicImagePreprocessor] so we can iterate safely.
class ExperimentalImagePreprocessor implements ImagePreprocessor {
  const ExperimentalImagePreprocessor();

  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) async {
    return compute(_processImageExperimental, bytes);
  }
}

PreprocessedResult _processImageExperimental(Uint8List bytes) {
  const int targetSize = 416;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format.');
  }

  img.Image processed = img.bakeOrientation(decoded);

  // Experimental pass:
  // 1) grayscale
  // 2) light contrast normalization
  // 3) mild blur (noise suppression)
  processed = img.grayscale(processed);
  processed = img.adjustColor(processed, contrast: 1.18, saturation: 0.0);
  processed = img.gaussianBlur(processed, radius: 1);

  final img.Image rgbImage = img.Image(
    width: processed.width,
    height: processed.height,
    numChannels: 3,
  );

  for (int y = 0; y < processed.height; y++) {
    for (int x = 0; x < processed.width; x++) {
      final pixel = processed.getPixel(x, y);
      final gray = pixel.r.toInt();
      rgbImage.setPixelRgb(x, y, gray, gray, gray);
    }
  }

  processed = rgbImage;

  final double scale =
      targetSize /
      (processed.width > processed.height ? processed.width : processed.height);
  final int padX = ((targetSize - (processed.width * scale).round()) / 2).round();
  final int padY = ((targetSize - (processed.height * scale).round()) / 2).round();

  processed = _letterbox(processed, targetSize);

  return PreprocessedResult(
    bytes: Uint8List.fromList(img.encodePng(processed)),
    width: processed.width,
    height: processed.height,
    scale: scale,
    padX: padX,
    padY: padY,
  );
}

img.Image _letterbox(img.Image src, int targetSize) {
  final double scale =
      targetSize / (src.width > src.height ? src.width : src.height);
  final int scaledW = (src.width * scale).round();
  final int scaledH = (src.height * scale).round();

  final resized = img.copyResize(
    src,
    width: scaledW,
    height: scaledH,
    interpolation: img.Interpolation.linear,
  );

  final canvas = img.Image(width: targetSize, height: targetSize);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  final int offsetX = ((targetSize - scaledW) / 2).round();
  final int offsetY = ((targetSize - scaledH) / 2).round();
  img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

  return canvas;
}
