class StaffPitchMapper {
  static const List<String> _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  /// Returns the bottom staff line reference note for a given clef sign.
  /// - G (treble) clef: bottom line = E4
  /// - F (bass) clef:   bottom line = G2
  static ({String step, int octave}) bottomLineRef(String clefSign) {
    if (clefSign.toUpperCase() == 'F') return (step: 'G', octave: 2);
    return (step: 'E', octave: 4);
  }

  /// Returns the diatonic step offset from the bottom line of the given clef.
  static int offsetFromBottomLine({
    required String step,
    required int octave,
    String clefSign = 'G',
  }) {
    final ref = bottomLineRef(clefSign);
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
  }) {
    final offset = offsetFromBottomLine(step: step, octave: octave, clefSign: clefSign);
    return bottomLineY - (offset * (lineSpacing / 2));
  }

  static StaffPitch pitchForY({
    required double y,
    required double bottomLineY,
    required double lineSpacing,
    String clefSign = 'G',
  }) {
    final ref = bottomLineRef(clefSign);
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
