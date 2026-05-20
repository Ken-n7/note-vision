import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

import 'symbol_classifier.dart';

/// Derives a plausible [DetectedStaff] from the bounding boxes of detected
/// symbols when the stave-detection step produced no results.
///
/// Line spacing is derived from the median notehead height using the standard
/// engraving proportion: notehead height ≈ 0.65 × inter-line spacing.
/// This is more reliable than spread-based estimation because a melody may
/// only span 2–3 lines, making the spread far smaller than the full staff.
///
/// The middle staff line (line 3) is anchored at the median notehead centre-Y
/// after trimming the outer 10 % to reduce ledger-line distortion.
///
/// Returns `null` when fewer than two noteheads are present.
class SyntheticStaffBuilder {
  static const double _minimumLineSpacing = 8.0;
  static const double _fallbackLineSpacing = 20.0;

  // Standard music engraving proportion: notehead height / inter-line spacing.
  static const double _noteheadHeightRatio = 0.65;

  const SyntheticStaffBuilder();

  DetectedStaff? build(List<DetectedSymbol> symbols) {
    final noteheads = symbols
        .where((s) => SymbolClassifier.isNotehead(s.type))
        .toList();

    if (noteheads.length < 2) return null;

    // Derive line spacing from median notehead height.
    final heights = noteheads
        .map((s) => s.height ?? 0.0)
        .where((h) => h > 0)
        .toList()
      ..sort();

    final double lineSpacing;
    if (heights.isNotEmpty) {
      final medianHeight = heights[heights.length ~/ 2];
      lineSpacing =
          (medianHeight / _noteheadHeightRatio).clamp(_minimumLineSpacing, double.infinity);
    } else {
      lineSpacing = _fallbackLineSpacing;
    }

    // Anchor the middle staff line at the median notehead centre-Y.
    // Trim outer 10 % first to reduce ledger-line distortion.
    final centerYs = noteheads
        .map((s) => s.y + ((s.height ?? 0) / 2))
        .toList()
      ..sort();

    final trimCount = (centerYs.length * 0.1).round();
    final trimmed = centerYs.sublist(trimCount, centerYs.length - trimCount);
    if (trimmed.isEmpty) return null;

    final medianY = trimmed[trimmed.length ~/ 2];

    final lineYs = List<double>.generate(
      5,
      (i) => medianY + (i - 2) * lineSpacing,
    );

    return DetectedStaff(
      id: 'synthetic-staff-0',
      topY: lineYs.first - lineSpacing,
      bottomY: lineYs.last + lineSpacing,
      lineYs: lineYs,
    );
  }
}
