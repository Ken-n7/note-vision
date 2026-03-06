// import 'dart:typed_data'; 
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
  // Step 1 — Decode + auto EXIF orientation correction
  final img.Image image = img.decodeImage(bytes)!;
  img.Image processed = img.bakeOrientation(image);

  // Step 2 — Grayscale
  processed = img.grayscale(processed);

  // Step 3 — Contrast / brightness adjustment
  processed = img.adjustColor(
    processed,
    contrast: 1.8,
    // brightness: 0.05,
  );

  // Step 4 — Light noise reduction (smooth before binarizing)
  processed = img.smooth(processed, weight: 1.5);

  // Step 5 — Binarize
  processed = img.luminanceThreshold(
    processed,
    threshold: 0.5,
    outputColor: false,
  );

  // Calculate letterbox metadata BEFORE resizing
  // using the image dimensions at this point
  const int targetSize = 640;
  final double scale = targetSize / (processed.width > processed.height ? processed.width : processed.height);
  final int padX = ((targetSize - (processed.width * scale).round()) / 2).round();
  final int padY = ((targetSize - (processed.height * scale).round()) / 2).round();

  // Step 6 — Resize to 640x640 with white padding (letterbox)
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
  // Scale down to fit within targetSize while keeping aspect ratio
  final double scale = targetSize / (src.width > src.height ? src.width : src.height);
  final int scaledW = (src.width * scale).round();
  final int scaledH = (src.height * scale).round();

  final img.Image resized = img.copyResize(
    src,
    width: scaledW,
    height: scaledH,
    interpolation: img.Interpolation.linear,
  );

  // Create white 640x640 canvas
  final img.Image canvas = img.Image(
    width: targetSize,
    height: targetSize,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  // Paste resized image centered on canvas
  final int offsetX = ((targetSize - scaledW) / 2).round();
  final int offsetY = ((targetSize - scaledH) / 2).round();

  img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

  return canvas;
}