import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'mapping_types.dart';

class PitchCalculator {
  const PitchCalculator();

  Pitch? calculate(DetectedSymbol symbol, DetectedStaff staff) {
    if (staff.lineYs.length < 2) return null;

    final sortedLines = [...staff.lineYs]..sort();
    final spacing = _averageSpacing(sortedLines);
    if (spacing <= 0) return null;

    final centerY = symbol.y + ((symbol.height ?? 0) / 2);
    final offset = ((sortedLines.last - centerY) / (spacing / 2)).round();

    return _fromTrebleOffset(offset);
  }

  double _averageSpacing(List<double> sortedLines) {
    if (sortedLines.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < sortedLines.length; i++) {
      total += (sortedLines[i] - sortedLines[i - 1]).abs();
    }
    return total / (sortedLines.length - 1);
  }

  Pitch _fromTrebleOffset(int offset) {
    const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    var stepIndex = 2 + offset; // base: E4 = index 2
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