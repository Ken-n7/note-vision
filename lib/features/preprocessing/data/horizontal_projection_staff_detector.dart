import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../detection/domain/detected_staff.dart';
import '../domain/staff_line_detector.dart';

/// Staff line pre-pass using horizontal projection.
///
/// Algorithm:
///   1. Decode the PNG (already grayscale-as-RGB from BasicImagePreprocessor).
///   2. Build a horizontal projection profile: for each row, count the number
///      of dark pixels (value < [_darkThreshold]).
///   3. A row is a "staff line" candidate when its dark-pixel count exceeds
///      [_lineMinDarkFraction] × imageWidth.
///   4. Cluster consecutive candidate rows into individual line bands.
///   5. Take the centre Y of each band as one staff line.
///   6. Group consecutive lines into staves of exactly 5 lines each.
///      Lines with an inter-line gap larger than [_maxInterLineGapMultiplier]
///      × the median inter-line spacing start a new stave.
///
/// All outputs are in original-image pixel coordinates so downstream code
/// can use them directly for stave-crop boundaries (topY, bottomY) and
/// pitch calculation (lineYs).
class HorizontalProjectionStaffDetector implements StaffLineDetector {
  const HorizontalProjectionStaffDetector({
    int darkThreshold = 128,
    double lineMinDarkFraction = 0.25,
    double maxInterLineGapMultiplier = 2.5,
    int minBandRows = 1,
  }) : _darkThreshold = darkThreshold,
       _lineMinDarkFraction = lineMinDarkFraction,
       _maxInterLineGapMultiplier = maxInterLineGapMultiplier,
       _minBandRows = minBandRows;

  /// Pixel luminance below which a pixel is counted as "dark".
  final int _darkThreshold;

  /// Fraction of image width that must be dark for a row to be a line candidate.
  final double _lineMinDarkFraction;

  /// An inter-line gap more than this multiple of the median spacing breaks
  /// the current stave and starts a new one.
  final double _maxInterLineGapMultiplier;

  /// Minimum consecutive dark rows needed to form a line band.
  final int _minBandRows;

  @override
  List<DetectedStaff> detect(Uint8List pngBytes) {
    final image = img.decodeImage(pngBytes);
    if (image == null) return [];

    final width = image.width;
    final height = image.height;
    final minDarkPixels = (_lineMinDarkFraction * width).round();

    // --- Step 1: horizontal projection ---
    final darkCounts = List<int>.filled(height, 0);
    for (int y = 0; y < height; y++) {
      int count = 0;
      for (int x = 0; x < width; x++) {
        if (image.getPixel(x, y).r < _darkThreshold) count++;
      }
      darkCounts[y] = count;
    }

    // --- Step 2: find candidate rows ---
    final isCandidate = List<bool>.filled(height, false);
    for (int y = 0; y < height; y++) {
      isCandidate[y] = darkCounts[y] >= minDarkPixels;
    }

    // --- Step 3: cluster consecutive candidates into bands ---
    final lineCentres = <double>[];
    int bandStart = -1;
    for (int y = 0; y <= height; y++) {
      final candidate = y < height && isCandidate[y];
      if (candidate && bandStart < 0) {
        bandStart = y;
      } else if (!candidate && bandStart >= 0) {
        final bandLen = y - bandStart;
        if (bandLen >= _minBandRows) {
          lineCentres.add(bandStart + bandLen / 2.0);
        }
        bandStart = -1;
      }
    }

    if (lineCentres.length < 5) return [];

    // --- Step 4: compute median inter-line spacing ---
    final gaps = <double>[];
    for (int i = 1; i < lineCentres.length; i++) {
      gaps.add(lineCentres[i] - lineCentres[i - 1]);
    }
    gaps.sort();
    final medianGap = gaps[gaps.length ~/ 2];

    // --- Step 5: group lines into staves of 5 ---
    final staves = <DetectedStaff>[];
    int staffIndex = 0;
    int i = 0;
    while (i < lineCentres.length) {
      // Collect lines for one stave: greedily take 5 lines whose gaps stay
      // within the allowed multiplier.
      final staveLines = <double>[lineCentres[i]];
      int j = i + 1;
      while (j < lineCentres.length && staveLines.length < 5) {
        final gap = lineCentres[j] - staveLines.last;
        if (gap > _maxInterLineGapMultiplier * medianGap) break;
        staveLines.add(lineCentres[j]);
        j++;
      }
      if (staveLines.length == 5) {
        // Extend top/bottom by half the inter-line spacing so the crop
        // includes space above line 1 and below line 5.
        final halfSpace = (staveLines[1] - staveLines[0]) / 2;
        staves.add(
          DetectedStaff(
            id: 'staff-$staffIndex',
            topY: (staveLines.first - halfSpace).clamp(0.0, height.toDouble()),
            bottomY: (staveLines.last + halfSpace).clamp(
              0.0,
              height.toDouble(),
            ),
            lineYs: staveLines,
          ),
        );
        staffIndex++;
        i = j;
      } else {
        // Could not form a complete stave — skip this line and try again.
        i++;
      }
    }

    return staves;
  }
}
