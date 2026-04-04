import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/image_preprocessor.dart';
import '../domain/preprocessed_result.dart';

class BasicImagePreprocessor implements ImagePreprocessor {
  @override
  Future<PreprocessedResult> preprocess(Uint8List bytes) async {
    return await compute(_processImage, bytes);
  }
}

PreprocessedResult _processImage(Uint8List bytes) {
  // Step 1 — Decode + EXIF orientation correction
  final img.Image image = img.decodeImage(bytes)!;
  img.Image processed = img.bakeOrientation(image);

  // Step 2 — Convert to grayscale then back to RGB
  // Matches training data: grayscale sheet music stored as RGB.
  processed = img.grayscale(processed);

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

  // Step 3 — Return full-resolution image (no resize).
  // The 640×640 stretch happens inside TfliteSymbolDetector to match training.
  return PreprocessedResult(
    bytes: Uint8List.fromList(img.encodePng(processed)),
    width: processed.width,
    height: processed.height,
    scale: 1.0,
    padX: 0,
    padY: 0,
  );
}
