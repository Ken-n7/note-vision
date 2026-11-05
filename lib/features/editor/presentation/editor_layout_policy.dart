import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_display_projection.dart';
import 'dart:math' as math;

import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/lyric_layout.dart';
import 'package:note_vision/core/widgets/score_notation/annotation_layout.dart';

class EditorLayoutPolicy {
  const EditorLayoutPolicy({
    required this.measuresPerRow,
    required this.rowsPerPage,
    this.pageWidth = 760.0,
    this.pageHeight = 1120.0,
    this.horizontalPadding = 16.0,
    this.verticalPadding = 28.0,
    this.rowHeight = 140.0,
    this.rowPrefixWidth = 86.0,
    this.notationTopPadding = 0,
  }) : assert(measuresPerRow > 0),
       assert(rowsPerPage > 0);

  static const standard = EditorLayoutPolicy(measuresPerRow: 4, rowsPerPage: 5);

  static final _policies = Expando<EditorLayoutPolicy>();
  factory EditorLayoutPolicy.forScore(Score score) =>
      _policies[score] ??= _forScore(score);
  static EditorLayoutPolicy _forScore(Score score) {
    final display = ScoreDisplayProjection.forScore(score);
    score = display.score;
    final clearance = EngravingLayout.forScore(score).clearance;
    final base = EditorLayoutPolicy.forPartCount(
      score.parts.length,
      extraHeight:
          clearance.$1 +
          clearance.$2 +
          LyricLayout.extraHeight(score.parts.map((p) => p.measures)) +
          AnnotationLayout.extraHeight(
            score.parts.map((p) => p.measures).toList(),
          ),
    );
    final extraTop =
        clearance.$1 +
        LyricLayout.aboveHeight(EngravingLayout.forScore(score).parts) +
        AnnotationLayout.aboveHeight(EngravingLayout.forScore(score).parts);
    final requiredWidth = EngravingLayout.forScore(score).minimumBarWidth;
    final available =
        base.pageWidth - base.horizontalPadding * 2 - base.rowPrefixWidth;
    final perRow = display.sequential
        ? display.columns
        : (available / requiredWidth).floor().clamp(1, base.measuresPerRow);
    final rowsPerPage = display.sequential
        ? display.rowsPerPage
        : base.rowsPerPage;
    return EditorLayoutPolicy(
      measuresPerRow: perRow,
      rowsPerPage: rowsPerPage,
      notationTopPadding: extraTop,
      pageWidth: math.max(
        base.pageWidth,
        requiredWidth * (display.sequential ? perRow : 1) +
            base.horizontalPadding * 2 +
            base.rowPrefixWidth,
      ),
      pageHeight: math.max(
        base.pageHeight,
        rowsPerPage * math.max(1, score.parts.length) * base.rowHeight +
            base.verticalPadding * 2 +
            88 +
            LyricLayout.aboveHeight(score.parts.map((p) => p.measures)) +
            AnnotationLayout.aboveHeight(
              score.parts.map((p) => p.measures).toList(),
            ) +
            clearance.$1,
      ),
      horizontalPadding: base.horizontalPadding,
      verticalPadding: base.verticalPadding,
      rowHeight: base.rowHeight,
      rowPrefixWidth: base.rowPrefixWidth,
    );
  }

  factory EditorLayoutPolicy.forPartCount(
    int partCount, {
    double extraHeight = 0,
  }) {
    const base = EditorLayoutPolicy.standard;
    final normalizedPartCount = math.max(1, partCount);
    final availableHeight = base.pageHeight - (base.verticalPadding * 2) - 88;
    final maxRowsThatFit =
        (availableHeight /
                (normalizedPartCount * (base.rowHeight + extraHeight)))
            .floor();
    final rowsPerPage = math.max(1, math.min(base.rowsPerPage, maxRowsThatFit));

    return EditorLayoutPolicy(
      measuresPerRow: base.measuresPerRow,
      rowsPerPage: rowsPerPage,
      pageWidth: base.pageWidth,
      pageHeight: base.pageHeight,
      horizontalPadding: base.horizontalPadding,
      verticalPadding: base.verticalPadding,
      rowHeight: base.rowHeight + extraHeight,
      rowPrefixWidth: base.rowPrefixWidth,
    );
  }

  final int measuresPerRow;
  final int rowsPerPage;
  final double pageWidth;
  final double pageHeight;
  final double horizontalPadding;
  final double verticalPadding;
  final double rowHeight;
  final double rowPrefixWidth;
  final double notationTopPadding;

  int get measuresPerPage => measuresPerRow * rowsPerPage;

  double get minMeasureWidth =>
      (pageWidth - horizontalPadding * 2 - rowPrefixWidth) / measuresPerRow;
}

int pageIndexForMeasure(List<int> pageStartIndices, int measureIndex) {
  if (pageStartIndices.isEmpty) {
    return 0;
  }

  var low = 0;
  var high = pageStartIndices.length - 1;
  var result = 0;

  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    if (pageStartIndices[mid] <= measureIndex) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return result;
}

List<int> pageStartIndicesForMeasures(
  List<Measure> measures, {
  EditorLayoutPolicy layoutPolicy = EditorLayoutPolicy.standard,
}) {
  if (measures.isEmpty) {
    return const [0];
  }

  final indices = <int>[0];
  for (var i = 1; i < measures.length; i++) {
    if (measures[i].startsNewPage ||
        i - indices.last >= layoutPolicy.measuresPerPage) {
      indices.add(i);
    }
  }
  return indices;
}

class EditorPageMetrics {
  const EditorPageMetrics({
    required this.layoutPolicy,
    required this.pageStartIndices,
    required this.currentPageIndex,
    required this.totalMeasures,
  });

  final EditorLayoutPolicy layoutPolicy;
  final List<int> pageStartIndices;
  final int currentPageIndex;
  final int totalMeasures;

  int get totalPages => pageStartIndices.length;

  int get pageFirstMeasure =>
      pageStartIndices[currentPageIndex.clamp(0, pageStartIndices.length - 1)];

  int get pageMeasureCount {
    final clamped = currentPageIndex.clamp(0, pageStartIndices.length - 1);
    final next = clamped + 1 < pageStartIndices.length
        ? pageStartIndices[clamped + 1]
        : totalMeasures;
    return math.max(0, next - pageStartIndices[clamped]);
  }

  int pageIndexForMeasureIndex(int measureIndex) =>
      pageIndexForMeasure(pageStartIndices, measureIndex);
}

final _layoutReferences = Expando<List<Measure>>();
List<Measure> layoutMeasuresForScore(Score score) =>
    _layoutReferences[score] ??= () {
      final display = ScoreDisplayProjection.forScore(score);
      if (display.sequential) return display.score.parts.first.measures;
      final parts = score.parts;
      final count = parts.fold(0, (n, p) => math.max(n, p.measures.length));
      return [
        for (var m = 0; m < count; m++)
          () {
            final measures = [
              for (final p in parts)
                if (m < p.measures.length) p.measures[m],
            ];
            return measures.first.copyWith(
              startsNewPage: measures.any((b) => b.startsNewPage),
            );
          }(),
      ];
    }();
