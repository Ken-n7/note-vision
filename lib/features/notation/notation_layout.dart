import 'dart:ui';

/// All visual constants for the notation renderer.
///
/// The staff uses 4 spaces between 5 lines.
/// [lineSpacing] is the distance between two adjacent lines.
/// A "staff slot" is half a [lineSpacing] — each line and space
/// between lines is one slot apart.
class NotationLayout {
  const NotationLayout._();

  // ── Staff geometry ─────────────────────────────────────────────
  static const double lineSpacing   = 10.0;  // px between adjacent lines
  static const double slotHeight    = lineSpacing / 2; // px per slot
  static const double staffHeight   = lineSpacing * 4; // top to bottom line
  static const double staffPadTop   = 48.0;  // space above staff (clef, numbers)
  static const double staffPadBot   = 40.0;  // space below staff (ledger area)
  static const double rowHeight     = staffPadTop + staffHeight + staffPadBot;

  // ── Measure layout ─────────────────────────────────────────────
  static const double clefWidth     = 28.0;
  static const double timeSigWidth  = 20.0;
  static const double keySigWidth   = 14.0; // per accidental
  static const double barlineWidth  = 1.5;
  static const double measureMinWidth = 120.0;
  static const double noteSpacing   = 32.0;  // px between symbols in a measure
  static const double measurePadL   = 12.0;  // padding inside measure before first note
  static const double measurePadR   = 12.0;

  // ── Notehead sizes ─────────────────────────────────────────────
  static const double noteheadW     = 9.0;
  static const double noteheadH     = 7.0;
  static const double stemLength    = 32.0;
  static const double stemWidth     = 1.2;
  static const double flagWidth     = 10.0;
  static const double ledgerW       = 14.0;  // ledger line half-width each side

  // ── Colors ────────────────────────────────────────────────────
  static const Color inkColor       = Color(0xFFE8E8E8);   // notation ink on dark bg
  static const Color staffColor     = Color(0xFF3A3A3A);   // staff lines
  static const Color measureNumColor = Color(0xFF6A6A6A);  // measure number text
}

/// Maps a note pitch (step + octave) to a vertical staff slot number.
///
/// In treble clef, the staff lines (bottom to top) are:
///   Line 1 (bottom) = E4  → slot 0
///   Space 1         = F4  → slot 1
///   Line 2          = G4  → slot 2
///   Space 2         = A4  → slot 3
///   Line 3 (middle) = B4  → slot 4
///   Space 3         = C5  → slot 5
///   Line 4          = D5  → slot 6
///   Space 4         = E5  → slot 7
///   Line 5 (top)    = F5  → slot 8
///
/// Middle C (C4) = slot -2 (one ledger line below staff).
/// Slot 0 is the bottom staff line (E4).
/// Higher slots → higher pitch → lower Y pixel value.
///
/// Formula:
///   1. Map step letter to chromatic offset within octave (diatonic, not chromatic).
///   2. Compute absolute diatonic position: octave * 7 + stepIndex.
///   3. Subtract the absolute diatonic position of E4 (the bottom line) to get slot.
class PitchToSlot {
  const PitchToSlot._();

  // Diatonic step index: C=0, D=1, E=2, F=3, G=4, A=5, B=6
  static const Map<String, int> _stepIndex = {
    'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6,
  };

  // E4 absolute diatonic position = 4*7 + 2 = 30
  static const int _e4Absolute = 30;

  /// Returns the staff slot for [step] (e.g. 'C', 'D' … 'B') at [octave].
  /// Slot 0 = E4 (bottom line of treble clef).
  /// Positive = higher on staff, negative = below staff.
  static int slot(String step, int octave) {
    final idx = _stepIndex[step.toUpperCase()] ?? 0;
    final absolute = octave * 7 + idx;
    return absolute - _e4Absolute;
  }

  /// Converts a slot number to a Y pixel offset from the top of the staff.
  ///
  /// Slot 0 (E4, bottom line) → y = staffHeight (40px from top of staff).
  /// Slot 8 (F5, top line)   → y = 0 (top of staff).
  /// Each slot is [NotationLayout.slotHeight] pixels.
  static double slotToY(int slotNum) {
    // Bottom line is slot 0 → y = staffHeight
    // Each slot up reduces y by slotHeight
    return NotationLayout.staffHeight - slotNum * NotationLayout.slotHeight;
  }

  /// Whether a note at [slotNum] needs a stem going up.
  /// Notes on or below the middle line (slot 4, B4) stem up.
  static bool stemUp(int slotNum) => slotNum <= 4;

  /// Ledger line slots relative to the staff.
  /// Below: slot -2 (C4), -4 (A3), -6 (F3) etc.
  /// Above: slot 10 (A5), 12 (C6) etc.
  static List<int> ledgerSlotsFor(int slotNum) {
    final ledgers = <int>[];
    if (slotNum < 0) {
      // below staff: even slots only (the lines, not spaces)
      for (int s = -2; s >= slotNum; s -= 2) {
        ledgers.add(s);
      }
    } else if (slotNum > 8) {
      // above staff
      for (int s = 10; s <= slotNum; s += 2) {
        ledgers.add(s);
      }
    }
    return ledgers;
  }
}