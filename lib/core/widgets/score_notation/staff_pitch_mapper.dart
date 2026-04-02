class StaffPitchMapper {
  static const List<String> _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  /// Returns the diatonic step offset from E4 (treble bottom line).
  ///
  /// Every +1 offset means one staff step upward (line->space or space->line).
  ///
  /// Formula:
  /// absoluteDiatonic = octave * 7 + stepIndex(C=0..B=6)
  /// offsetFromE4 = absoluteDiatonic - absoluteDiatonic(E4)
  static int offsetFromTrebleBottomLine({
    required String step,
    required int octave,
  }) {
    final normalized = step.trim().toUpperCase();
    final stepIndex = _steps.indexOf(normalized);
    if (stepIndex < 0) return 0;

    const e4Index = 2; // E in C D E F G A B.
    const e4Absolute = 4 * 7 + e4Index;
    final absolute = octave * 7 + stepIndex;
    return absolute - e4Absolute;
  }

  static double yForPitch({
    required String step,
    required int octave,
    required double bottomLineY,
    required double lineSpacing,
  }) {
    final offset = offsetFromTrebleBottomLine(step: step, octave: octave);
    return bottomLineY - (offset * (lineSpacing / 2));
  }

  static StaffPitch pitchForY({
    required double y,
    required double bottomLineY,
    required double lineSpacing,
  }) {
    const e4Index = 2;
    const e4Absolute = 4 * 7 + e4Index;

    final offset = ((bottomLineY - y) / (lineSpacing / 2)).round();
    final absolute = e4Absolute + offset;
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
