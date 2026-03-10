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
  const int targetSize = 416;

  // Step 1 — Decode + EXIF orientation correction
  final img.Image image = img.decodeImage(bytes)!;
  img.Image processed = img.bakeOrientation(image);

  // Step 2 — Convert to grayscale then back to RGB
  // matches training data: grayscale sheet music stored as RGB
  // convert to grayscale then back to RGB
  // matches training data: grayscale sheet music stored as RGB
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

  // Step 3 — Letterbox resize to 416x416 with white padding
  final double scale =
      targetSize /
      (processed.width > processed.height ? processed.width : processed.height);
  final int padX = ((targetSize - (processed.width * scale).round()) / 2)
      .round();
  final int padY = ((targetSize - (processed.height * scale).round()) / 2)
      .round();

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

  final img.Image resized = img.copyResize(
    src,
    width: scaledW,
    height: scaledH,
    interpolation: img.Interpolation.linear,
  );

  // white canvas to match sheet music background
  final img.Image canvas = img.Image(width: targetSize, height: targetSize);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  final int offsetX = ((targetSize - scaledW) / 2).round();
  final int offsetY = ((targetSize - scaledH) / 2).round();

  img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

  return canvas;
}
