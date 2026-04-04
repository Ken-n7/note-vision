import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

import 'symbol_classifier.dart';

/// Derives a plausible [DetectedStaff] from the bounding boxes of detected
/// symbols when the stave-detection step produced no results.
///
/// The geometry is estimated from notehead vertical positions:
/// - The middle staff line is anchored at the median notehead centre-Y.
/// - Line spacing is estimated from the trimmed vertical spread divided by 4
///   (a 5-line staff spans exactly 4 inter-line spaces).
/// - The top/bottom 10 % of notehead Y values are discarded before computing
///   the spread so that ledger-line noteheads do not inflate the estimate.
///
/// Returns `null` when fewer than two noteheads are present, which means there
/// is not enough geometry to make a meaningful estimate.
class SyntheticStaffBuilder {
  static const double _minimumLineSpacing = 8.0;
  static const double _fallbackLineSpacing = 20.0;

  const SyntheticStaffBuilder();

  DetectedStaff? build(List<DetectedSymbol> symbols) {
    final centerYs = symbols
        .where((s) => SymbolClassifier.isNotehead(s.type))
        .map((s) => s.y + ((s.height ?? 0) / 2))
        .toList()
      ..sort();

    if (centerYs.length < 2) return null;

    // Trim the outer 10 % from each end to reduce ledger-line distortion.
    final trimCount = (centerYs.length * 0.1).round();
    final trimmed = centerYs.sublist(
      trimCount,
      centerYs.length - trimCount,
    );

    if (trimmed.isEmpty) return null;

    final medianY = trimmed[trimmed.length ~/ 2];
    final spread = trimmed.last - trimmed.first;

    // A 5-line staff spans 4 inter-line spaces.
    final rawSpacing = spread > 0 ? spread / 4 : _fallbackLineSpacing;
    final lineSpacing = rawSpacing.clamp(_minimumLineSpacing, double.infinity);

    // Build 5 lines centred on the median notehead Y.
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
