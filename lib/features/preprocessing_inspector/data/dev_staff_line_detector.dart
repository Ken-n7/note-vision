import 'dart:math' as math;
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

class DevStaffGroup {
  const DevStaffGroup({
    required this.lines,
    required this.averageSpacing,
  });

  final List<DevStaffLine> lines;
  final double averageSpacing;
}

class DevStaffLineDetectorConfig {
  const DevStaffLineDetectorConfig({
    this.darkPixelThreshold = 120,
    this.minDarkRatio = 0.24,
    this.smoothingWindow = 7,
    this.minPeakProminence = 0.008,
    this.minPeakDistance = 6,
    this.groupSpacingTolerance = 0.35,
  });

  final int darkPixelThreshold;
  final double minDarkRatio;
  final int smoothingWindow;
  final double minPeakProminence;
  final int minPeakDistance;
  final double groupSpacingTolerance;
}

class DevStaffLineDetectionResult {
  const DevStaffLineDetectionResult({
    required this.width,
    required this.height,
    required this.lines,
    required this.groups,
    required this.darkRows,
    required this.minDarkRatio,
  });

  final int width;
  final int height;
  final List<DevStaffLine> lines;
  final List<DevStaffGroup> groups;
  final int darkRows;
  final double minDarkRatio;

  bool get hasLines => lines.isNotEmpty;
}

class DevStaffLineDetector {
  const DevStaffLineDetector();

  Future<DevStaffLineDetectionResult> detect(
    Uint8List preprocessedBytes, {
    DevStaffLineDetectorConfig config = const DevStaffLineDetectorConfig(),
  }) {
    return compute(_detectStaffLines, _DetectInput(preprocessedBytes, config));
  }
}

class _DetectInput {
  const _DetectInput(this.bytes, this.config);

  final Uint8List bytes;
  final DevStaffLineDetectorConfig config;
}

DevStaffLineDetectionResult _detectStaffLines(_DetectInput input) {
  final image = img.decodeImage(input.bytes);
  if (image == null) {
    throw const FormatException('Unable to decode preprocessed image bytes.');
  }

  final width = image.width;
  final height = image.height;
  final config = input.config;

  final darknessByRow = List<double>.filled(height, 0);
  final darkRows = <int>[];

  for (int y = 0; y < height; y++) {
    var darkCount = 0;
    for (int x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      if (p.r <= config.darkPixelThreshold) darkCount++;
    }
    final ratio = darkCount / width;
    darknessByRow[y] = ratio;
    if (ratio >= config.minDarkRatio) {
      darkRows.add(y);
    }
  }

  final smooth = _movingAverage(darknessByRow, config.smoothingWindow);
  final peakIndices = _pickPeaks(
    smooth,
    minY: 2,
    maxY: math.max(2, height - 3),
    minDarkRatio: config.minDarkRatio,
    minProminence: config.minPeakProminence,
    minDistance: config.minPeakDistance,
  );

  final lines = peakIndices
      .map(
        (y) => DevStaffLine(
          y: y.toDouble(),
          darknessRatio: smooth[y],
          thickness: _estimateThickness(smooth, y),
        ),
      )
      .toList(growable: false);

  final groups = _groupIntoStaffs(lines, config.groupSpacingTolerance);

  return DevStaffLineDetectionResult(
    width: width,
    height: height,
    lines: lines,
    groups: groups,
    darkRows: darkRows.length,
    minDarkRatio: config.minDarkRatio,
  );
}

List<double> _movingAverage(List<double> values, int window) {
  final safeWindow = math.max(1, window.isOdd ? window : window + 1);
  final radius = safeWindow ~/ 2;

  return List<double>.generate(values.length, (i) {
    var sum = 0.0;
    var count = 0;
    for (int j = i - radius; j <= i + radius; j++) {
      if (j < 0 || j >= values.length) continue;
      sum += values[j];
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }, growable: false);
}

List<int> _pickPeaks(
  List<double> signal, {
  required int minY,
  required int maxY,
  required double minDarkRatio,
  required double minProminence,
  required int minDistance,
}) {
  final candidates = <int>[];

  for (int y = minY; y <= maxY; y++) {
    final center = signal[y];
    if (center < minDarkRatio) continue;

    final left = signal[y - 1];
    final right = signal[y + 1];
    if (center < left || center < right) continue;

    final localMinLeft = math.min(signal[y - 1], signal[y - 2]);
    final localMinRight = math.min(signal[y + 1], signal[y + 2]);
    final prominence = center - math.max(localMinLeft, localMinRight);
    if (prominence < minProminence) continue;

    candidates.add(y);
  }

  candidates.sort((a, b) => signal[b].compareTo(signal[a]));

  final picked = <int>[];
  for (final y in candidates) {
    final tooClose = picked.any((p) => (p - y).abs() < minDistance);
    if (!tooClose) {
      picked.add(y);
    }
  }

  picked.sort();
  return picked;
}

int _estimateThickness(List<double> signal, int centerY) {
  final baseline = signal[centerY] * 0.75;
  var top = centerY;
  var bottom = centerY;

  while (top > 0 && signal[top - 1] >= baseline) {
    top--;
  }
  while (bottom < signal.length - 1 && signal[bottom + 1] >= baseline) {
    bottom++;
  }

  return (bottom - top) + 1;
}

List<DevStaffGroup> _groupIntoStaffs(
  List<DevStaffLine> lines,
  double spacingTolerance,
) {
  if (lines.length < 5) return const [];

  final groups = <DevStaffGroup>[];

  for (int i = 0; i <= lines.length - 5; i++) {
    final candidate = lines.sublist(i, i + 5);
    final spacings = <double>[];
    for (int j = 0; j < 4; j++) {
      spacings.add(candidate[j + 1].y - candidate[j].y);
    }

    final avg = spacings.reduce((a, b) => a + b) / spacings.length;
    if (avg <= 0) continue;

    final withinTolerance = spacings.every(
      (s) => ((s - avg).abs() / avg) <= spacingTolerance,
    );

    if (withinTolerance) {
      groups.add(DevStaffGroup(lines: List.of(candidate), averageSpacing: avg));
      i += 4;
    }
  }

  return groups;
}
