import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DevStaffLine {
  const DevStaffLine({
    required this.y,
    required this.darknessRatio,
    required this.thickness,
  });

  final double y;
  final double darknessRatio;
  final int thickness;
}

class DevStaffLineDetectionResult {
  const DevStaffLineDetectionResult({
    required this.width,
    required this.height,
    required this.lines,
    required this.darkRows,
    required this.minDarkRatio,
  });

  final int width;
  final int height;
  final List<DevStaffLine> lines;
  final int darkRows;
  final double minDarkRatio;

  bool get hasLines => lines.isNotEmpty;
}

class DevStaffLineDetector {
  const DevStaffLineDetector();

  Future<DevStaffLineDetectionResult> detect(Uint8List preprocessedBytes) {
    return compute(_detectStaffLines, preprocessedBytes);
  }
}

DevStaffLineDetectionResult _detectStaffLines(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Unable to decode preprocessed image bytes.');
  }

  final width = image.width;
  final height = image.height;

  // Tuned for preprocessed monochrome-ish sheet images.
  const darkPixelThreshold = 110;
  const minDarkRatio = 0.32;
  const minBandThickness = 1;

  final darknessByRow = List<double>.filled(height, 0);
  final candidates = <int>[];

  for (int y = 0; y < height; y++) {
    var darkCount = 0;
    for (int x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      if (p.r <= darkPixelThreshold) darkCount++;
    }
    final ratio = darkCount / width;
    darknessByRow[y] = ratio;
    if (ratio >= minDarkRatio) {
      candidates.add(y);
    }
  }

  if (candidates.isEmpty) {
    return DevStaffLineDetectionResult(
      width: width,
      height: height,
      lines: const [],
      darkRows: 0,
      minDarkRatio: minDarkRatio,
    );
  }

  final lines = <DevStaffLine>[];

  var start = candidates.first;
  var previous = candidates.first;

  void flushBand(int from, int to) {
    final thickness = (to - from) + 1;
    if (thickness < minBandThickness) return;

    double weightedY = 0;
    double totalWeight = 0;
    for (int y = from; y <= to; y++) {
      final weight = darknessByRow[y];
      weightedY += y * weight;
      totalWeight += weight;
    }
    final centerY = totalWeight > 0 ? weightedY / totalWeight : (from + to) / 2;

    var best = 0.0;
    for (int y = from; y <= to; y++) {
      if (darknessByRow[y] > best) best = darknessByRow[y];
    }

    lines.add(
      DevStaffLine(
        y: centerY,
        darknessRatio: best,
        thickness: thickness,
      ),
    );
  }

  for (final y in candidates.skip(1)) {
    if (y == previous + 1) {
      previous = y;
      continue;
    }

    flushBand(start, previous);
    start = y;
    previous = y;
  }
  flushBand(start, previous);

  return DevStaffLineDetectionResult(
    width: width,
    height: height,
    lines: lines,
    darkRows: candidates.length,
    minDarkRatio: minDarkRatio,
  );
}
