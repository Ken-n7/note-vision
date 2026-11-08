import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/score.dart';

class ScanKeyRowChange {
  const ScanKeyRowChange(this.row, this.before, this.end, this.changedBars);
  final int row, end, changedBars;
  final KeySignature? before;
}

/// A user-chosen correction to the opening key of independent scan rows.
/// Later different keys are boundaries, including an explicit natural key.
class ScanKeyCorrection {
  const ScanKeyCorrection._(this.base, this.preview, this.changes);
  final Score base, preview;
  final List<ScanKeyRowChange> changes;
  bool get hasChanges => changes.isNotEmpty;

  static bool supports(Score score) =>
      score.isScannedMusic &&
      score.parts.length > 1 &&
      score.parts.every(
        (p) =>
            !p.joinsPrevious &&
            !p.linked &&
            !p.isTab &&
            !p.isPercussion &&
            p.staffLines == 5 &&
            p.measures.isNotEmpty,
      );

  static int openingEnd(Score score, int row) {
    final bars = score.parts[row].measures;
    final opening = bars.first.keySignature;
    for (var m = 1; m < bars.length; m++) {
      if (bars[m].keySignature != null && bars[m].keySignature != opening) {
        return m;
      }
    }
    return bars.length;
  }

  static ScanKeyCorrection prepare(Score score, Set<int> rows, int fifths) {
    if (!supports(score) ||
        fifths < -7 ||
        fifths > 7 ||
        rows.any((r) => r < 0 || r >= score.parts.length)) {
      return ScanKeyCorrection._(score, score, const []);
    }
    final parts = score.parts.toList();
    final changes = <ScanKeyRowChange>[];
    for (var p = 0; p < parts.length; p++) {
      if (!rows.contains(p)) continue;
      final bars = parts[p].measures.toList();
      final end = openingEnd(score, p);
      final key = KeySignature(fifths: fifths);
      var changed = 0;
      for (var m = 0; m < end; m++) {
        // Keep repeated inherited values consistent, including a previously
        // absent opening key. No note, written accidental or source is edited.
        if ((m > 0 && bars[m].keySignature == null) ||
            bars[m].keySignature == key) {
          continue;
        }
        bars[m] = bars[m].copyWith(keySignature: key);
        changed++;
      }
      if (changed == 0) continue;
      changes.add(
        ScanKeyRowChange(p, parts[p].measures.first.keySignature, end, changed),
      );
      parts[p] = parts[p].copyWith(measures: bars);
    }
    return ScanKeyCorrection._(
      score,
      changes.isEmpty ? score : score.copyWith(parts: parts),
      List.unmodifiable(changes),
    );
  }

  Score? applyTo(Score current) =>
      identical(current, base) && hasChanges ? preview : null;

  static String keyLabel(KeySignature? key) => switch (key?.fifths) {
    null => 'Not read',
    0 => 'No sharps or flats',
    final n =>
      '${n.abs()} ${n > 0 ? (n == 1 ? 'sharp ♯' : 'sharps ♯') : (n == -1 ? 'flat ♭' : 'flats ♭')}',
  };
}
