import '../../models/measure.dart';
import 'engraving_layout.dart';
import '../../models/musical_time.dart';

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
  static final _rows = Expando<Map<(AnnotationKind, bool), int>>();
  static Map<(AnnotationKind, bool), int> _rowCounts(
    List<List<Measure>> parts,
  ) => _rows[parts] ??= _countRows(parts);
  static Map<(AnnotationKind, bool), int> _countRows(
    List<List<Measure>> parts,
  ) {
    final result = <(AnnotationKind, bool), int>{};
    for (var p = 0; p < parts.length; p++) {
      for (var m = 0; m < parts[p].length; m++) {
        final counts = <(AnnotationKind, bool, MusicalTime), int>{};
        for (final (_, _, a) in at(parts, p, m)) {
          final key = (a.kind, a.below, a.offset), lane = (a.kind, a.below);
          final n = (counts[key] ?? 0) + 1;
          counts[key] = n;
          if (n > (result[lane] ?? 0)) result[lane] = n;
        }
      }
    }
    return result;
  }

  static List<AnnotationKind> kinds(List<List<Measure>> parts, bool below) => [
    for (final k in _rowCounts(parts).keys)
      if (k.$2 == below) k.$1,
  ]..sort((a, b) => a.index.compareTo(b.index));
  static int rowsFor(
    List<List<Measure>> parts,
    AnnotationKind kind,
    bool below,
  ) => _rowCounts(parts)[(kind, below)] ?? 1;
  static double lane(List<List<Measure>> parts, ScoreAnnotation annotation) {
    var row = 0;
    for (final k in kinds(parts, annotation.below)) {
      if (k == annotation.kind) break;
      row += rowsFor(parts, k, annotation.below);
    }
    return row * lineHeight;
  }

  static double aboveHeight(List<List<Measure>> parts) =>
      kinds(parts, false).fold(0, (n, k) => n + rowsFor(parts, k, false)) *
      lineHeight;
  static double extraHeight(List<List<Measure>> parts) =>
      aboveHeight(parts) +
      kinds(parts, true).fold(0, (n, k) => n + rowsFor(parts, k, true)) *
          lineHeight;
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
    BarPlacement? placement,
  }) {
    final placed =
        placement ??
        EngravingLayout([
          [visible],
        ]).bars.single.place(width: width, inset: inset);
    double xAt(MusicalTime at) => startX + placed.timeX(at);

    final clearance = EngravingLayout.verticalClearance(parts);
    final duplicates = <(AnnotationKind, bool, MusicalTime), int>{};
    final entries = at(parts, part, measure);
    double annotationLane(ScoreAnnotation a) {
      final key = (a.kind, a.below, a.offset);
      final duplicate = duplicates[key] ?? 0;
      duplicates[key] = duplicate + 1;
      return lane(parts, a) + duplicate * lineHeight;
    }

    final belowLyrics = {
      for (final m in parts[part])
        for (final n in m.notes)
          for (final l in n.lyrics)
            if (!l.hidden && !l.above) (n.voice ?? 1, n.staff ?? 1, l.verse),
    }.length;
    return [
      for (final (owner, i, a) in entries)
        AnnotationTextLayout(
          owner,
          i,
          a,
          xAt(a.offset),
          a.below
              ? staffBottom +
                    46 +
                    belowLyrics * 18 +
                    clearance.$2 +
                    annotationLane(a)
              : staffTop - 40 - lyricAbove - (clearance.$1 + annotationLane(a)),
        ),
    ];
  }
}
