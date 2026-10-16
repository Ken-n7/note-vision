import 'dart:math' as math;

/// Length in quarter notes of each written note or rest value.
///
/// A symbol's stored `duration` counts 2 divisions per quarter, so it cannot
/// hold a sixteenth (0.5) or a dotted eighth (1.5); timing therefore comes
/// from the written type and dots instead.
const Map<String, double> noteValueQuarters = {
  'breve': 8,
  'whole': 4,
  'half': 2,
  'quarter': 1,
  'eighth': 0.5,
  '16th': 0.25,
  'sixteenth': 0.25,
  '32nd': 0.125,
};

/// Length in quarter notes of a note or rest written as [type] with [dots]:
/// the first dot adds half the value, the second a quarter more. The stored
/// [divisions] (2 per quarter) are used only when the type is unknown.
double quarterLength(String type, int dots, int divisions) {
  final base = noteValueQuarters[type.trim().toLowerCase()];
  if (base == null) return divisions / 2;
  return base * (2 - math.pow(0.5, dots));
}
