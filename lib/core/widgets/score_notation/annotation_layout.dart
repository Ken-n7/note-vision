import 'dart:math' as math;
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/note_value.dart';
import 'voice_layout.dart';

class AnnotationTextLayout {
  const AnnotationTextLayout(
    this.owner,
    this.index,
    this.annotation,
    this.x,
    this.y,
  );
  final int owner, index;
  final ScoreAnnotation annotation;
  final double x, y;
}

abstract final class AnnotationLayout {
  static const lineHeight = 20.0, fontSize = 12.0;
  static List<AnnotationKind> kinds(List<List<Measure>> parts, bool below) => {
    for (final p in parts)
      for (final m in p)
        for (final a in m.annotations)
          if (!a.hidden && a.below == below) a.kind,
  }.toList()..sort((a, b) => a.index.compareTo(b.index));
  static double aboveHeight(List<List<Measure>> parts) =>
      kinds(parts, false).length * lineHeight;
  static double extraHeight(List<List<Measure>> parts) =>
      (kinds(parts, false).length + kinds(parts, true).length) * lineHeight;
  static List<(int, int, ScoreAnnotation)> at(
    List<List<Measure>> parts,
    int part,
    int measure,
  ) => [
    for (final (p, measures) in parts.indexed)
      if (measure < measures.length)
        for (final (i, a) in measures[measure].annotations.indexed)
          if (!a.hidden && (a.system ? part == 0 : part == p)) (p, i, a),
  ];
  static List<AnnotationTextLayout> build({
    required List<List<Measure>> parts,
    required int part,
    required int measure,
    required Measure visible,
    required double startX,
    required double width,
    required double staffTop,
    required double staffBottom,
    required double inset,
    double lyricAbove = 0,
  }) {
    final layout = VoiceLayout.of(visible.symbols);
    final positions = <double, double>{};
    final ends = <(int, int), double>{};
    var chordOnset = 0.0;
    for (final (i, s) in visible.symbols.indexed) {
      final lane = switch (s) {
        Note(:final voice, :final staff) ||
        Rest(:final voice, :final staff) => (voice ?? 1, staff ?? 1),
        _ => (1, 1),
      };
      final onset = s is Note && s.isChordTone ? chordOnset : ends[lane] ?? 0;
      if (!(s is Note && s.isChordTone)) {
        chordOnset = onset;
        ends[lane] = onset + symbolQuarters(s);
      }
      positions.putIfAbsent(
        onset,
        () =>
            startX +
            inset +
            (width - inset - 16) *
                (layout.columns[i] + 1) /
                (layout.columnCount + 1),
      );
    }
    final sorted = positions.keys.toList()..sort();
    double xAt(double at) {
      if (sorted.isEmpty) {
        final duration = (visible.timeSignature == null
            ? 4.0
            : visible.timeSignature!.beats *
                  4.0 /
                  visible.timeSignature!.beatType);
        return startX +
            inset +
            (width - inset - 16) * (at / duration).clamp(0, 1);
      }
      if (at <= sorted.first) return positions[sorted.first]!;
      for (var i = 1; i < sorted.length; i++) {
        if (at <= sorted[i]) {
          final a = sorted[i - 1], b = sorted[i];
          return positions[a]! +
              (positions[b]! - positions[a]!) * (at - a) / (b - a);
        }
      }
      final end = ends.values.fold(0.0, math.max);
      return positions[sorted.last]! +
          (startX + width - 12 - positions[sorted.last]!) *
              ((at - sorted.last) /
                      (end - sorted.last == 0 ? 1 : end - sorted.last))
                  .clamp(0, 1);
    }

    final belowLyrics = {
      for (final m in parts[part])
        for (final n in m.notes)
          for (final l in n.lyrics)
            if (!l.hidden && !l.above) (n.voice ?? 1, n.staff ?? 1, l.verse),
    }.length;
    return [
      for (final (owner, i, a) in at(parts, part, measure))
        AnnotationTextLayout(
          owner,
          i,
          a,
          xAt(a.offset.asDouble),
          a.below
              ? staffBottom +
                    46 +
                    belowLyrics * 18 +
                    kinds(parts, true).indexOf(a.kind) * lineHeight
              : staffTop -
                    40 -
                    lyricAbove -
                    kinds(parts, false).indexOf(a.kind) * lineHeight,
        ),
    ];
  }
}
