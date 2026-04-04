import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/core/models/clef.dart';
import 'mapping_types.dart';

class PitchCalculator {
  const PitchCalculator();

  Pitch? calculate({
    required DetectedSymbol symbol,
    required DetectedStaff staff,
    required Clef? clef,
  }) {
    if (clef == null) return null;
    if (clef.sign != 'G' && clef.sign != 'F') return null;
    if (staff.lineYs.length < 2) return null;

    final sortedLines = [...staff.lineYs]..sort();
    final spacing = _averageSpacing(sortedLines);
    if (spacing <= 0) return null;

    final centerY = symbol.y + ((symbol.height ?? 0) / 2);
    final diatonicOffset = _nearestDiatonicOffset(
      centerY: centerY,
      bottomLineY: sortedLines.last,
      lineSpacing: spacing,
    );

    return clef.sign == 'G'
        ? _fromTrebleOffset(diatonicOffset)
        : _fromBassOffset(diatonicOffset);
  }

  double _averageSpacing(List<double> sortedLines) {
    if (sortedLines.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < sortedLines.length; i++) {
      total += (sortedLines[i] - sortedLines[i - 1]).abs();
    }
    return total / (sortedLines.length - 1);
  }

  int _nearestDiatonicOffset({
    required double centerY,
    required double bottomLineY,
    required double lineSpacing,
  }) {
    final halfStepSpacing = lineSpacing / 2;
    return ((bottomLineY - centerY) / halfStepSpacing).round();
  }

  /// Bass clef: F clef on line 4. Bottom staff line (line 1) = G2.
  /// Offset 0 = G2, offset 2 = B2, offset 4 = D3, offset 6 = F3, offset 8 = A3.
  Pitch _fromBassOffset(int diatonicOffset) {
    const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    var stepIndex = 4 + diatonicOffset; // base: G2 → index 4
    var octave = 2;

    while (stepIndex < 0) {
      stepIndex += steps.length;
      octave--;
    }
    while (stepIndex >= steps.length) {
      stepIndex -= steps.length;
      octave++;
    }

    return Pitch(step: steps[stepIndex], octave: octave);
  }

  Pitch _fromTrebleOffset(int diatonicOffset) {
    const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    var stepIndex = 2 + diatonicOffset; // base: E4 = index 2
    var octave = 4;

    while (stepIndex < 0) {
      stepIndex += steps.length;
      octave--;
    }
    while (stepIndex >= steps.length) {
      stepIndex -= steps.length;
      octave++;
    }

    return Pitch(step: steps[stepIndex], octave: octave);
  }
}
