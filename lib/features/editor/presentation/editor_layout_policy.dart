import 'dart:math' as math;

import 'package:note_vision/core/models/measure.dart';

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
  }) : assert(measuresPerRow > 0),
       assert(rowsPerPage > 0);

  static const standard = EditorLayoutPolicy(
    measuresPerRow: 4,
    rowsPerPage: 5,
  );

  factory EditorLayoutPolicy.forPartCount(int partCount) {
    const base = EditorLayoutPolicy.standard;
    final normalizedPartCount = math.max(1, partCount);
    final availableHeight = base.pageHeight - (base.verticalPadding * 2);
    final maxRowsThatFit =
        (availableHeight / (normalizedPartCount * base.rowHeight)).floor();
    final rowsPerPage = math.max(
      1,
      math.min(base.rowsPerPage, maxRowsThatFit),
    );

    return EditorLayoutPolicy(
      measuresPerRow: base.measuresPerRow,
      rowsPerPage: rowsPerPage,
      pageWidth: base.pageWidth,
      pageHeight: base.pageHeight,
      horizontalPadding: base.horizontalPadding,
      verticalPadding: base.verticalPadding,
      rowHeight: base.rowHeight,
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

  final hasExplicitBreaks = measures.any((m) => m.startsNewPage);
  if (!hasExplicitBreaks) {
    final count = math.max(
      1,
      (measures.length + layoutPolicy.measuresPerPage - 1) ~/
          layoutPolicy.measuresPerPage,
    );
    return List.generate(count, (i) => i * layoutPolicy.measuresPerPage);
  }

  final indices = <int>[0];
  for (int i = 1; i < measures.length; i++) {
    if (measures[i].startsNewPage) {
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
