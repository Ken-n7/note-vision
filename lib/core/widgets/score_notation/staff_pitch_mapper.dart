class StaffPitchMapper {
  static const List<String> _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  /// Returns the bottom staff line reference note for a given clef sign.
  /// - G (treble) clef: bottom line = E4
  /// - F (bass) clef:   bottom line = G2
  /// - C clef: C4 sits on [clefLine]; bottom line derived by stepping down (clefLine-1)*2 diatonic steps.
  ///   Alto (line 3) → F3; Tenor (line 4) → D3.
  static ({String step, int octave}) bottomLineRef(
    String clefSign, {
    int clefLine = 2,
  }) {
    final sign = clefSign.toUpperCase();
    if (sign == 'F') return (step: 'G', octave: 2);
    if (sign == 'C') {
      // C4 absolute index: octave 4 * 7 steps + index of 'C' (0) = 28
      const c4Abs = 28;
      final bottomAbs = c4Abs - (clefLine - 1) * 2;
      final stepIdx = ((bottomAbs % _steps.length) + _steps.length) % _steps.length;
      final octave = (bottomAbs - stepIdx) ~/ _steps.length;
      return (step: _steps[stepIdx], octave: octave);
    }
    return (step: 'E', octave: 4);
  }

  /// Returns the diatonic step offset from the bottom line of the given clef.
  static int offsetFromBottomLine({
    required String step,
    required int octave,
    String clefSign = 'G',
    int clefLine = 2,
  }) {
    final ref = bottomLineRef(clefSign, clefLine: clefLine);
    final normalized = step.trim().toUpperCase();
    final stepIndex = _steps.indexOf(normalized);
    if (stepIndex < 0) return 0;
    final refIndex = _steps.indexOf(ref.step);
    final absolute = octave * 7 + stepIndex;
    final refAbsolute = ref.octave * 7 + refIndex;
    return absolute - refAbsolute;
  }

  /// Legacy name — kept for backward compatibility. Assumes treble clef.
  static int offsetFromTrebleBottomLine({
    required String step,
    required int octave,
  }) =>
      offsetFromBottomLine(step: step, octave: octave, clefSign: 'G');

  static double yForPitch({
    required String step,
    required int octave,
    required double bottomLineY,
    required double lineSpacing,
    String clefSign = 'G',
    int clefLine = 2,
  }) {
    final offset = offsetFromBottomLine(
      step: step,
      octave: octave,
      clefSign: clefSign,
      clefLine: clefLine,
    );
    return bottomLineY - (offset * (lineSpacing / 2));
  }

  static StaffPitch pitchForY({
    required double y,
    required double bottomLineY,
    required double lineSpacing,
    String clefSign = 'G',
    int clefLine = 2,
  }) {
    final ref = bottomLineRef(clefSign, clefLine: clefLine);
    final refIndex = _steps.indexOf(ref.step);
    final refAbsolute = ref.octave * 7 + refIndex;

    final offset = ((bottomLineY - y) / (lineSpacing / 2)).round();
    final absolute = refAbsolute + offset;
    final stepIndex = ((absolute % _steps.length) + _steps.length) % _steps.length;
    final octave = (absolute - stepIndex) ~/ _steps.length;
    return StaffPitch(step: _steps[stepIndex], octave: octave);
  }
}

class StaffPitch {
  const StaffPitch({required this.step, required this.octave});

  final String step;
  final int octave;
}
