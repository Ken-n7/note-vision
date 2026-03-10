import 'package:flutter/material.dart';
import 'music_symbol.dart';

class DetectedSymbol {
  final MusicSymbol symbol;
  final Rect boundingBox;     // in preprocessed image coordinates (640x640)
  final double confidence;

  const DetectedSymbol({
    required this.symbol,
    required this.boundingBox,
    required this.confidence,
  });

  // map bounding box back to original image coordinates
  Rect toOriginalCoordinates({
    required double scale,
    required int padX,
    required int padY,
  }) {
    return Rect.fromLTWH(
      (boundingBox.left - padX) / scale,
      (boundingBox.top - padY) / scale,
      boundingBox.width / scale,
      boundingBox.height / scale,
    );
  }
}