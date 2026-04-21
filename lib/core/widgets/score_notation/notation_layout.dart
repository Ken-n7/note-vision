import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/measure.dart';

class NotationLayout {
  const NotationLayout({
    required this.size,
    required this.rowPrefixWidth,
    required this.rowCount,
    required this.measuresPerRow,
  });

  final Size size;
  final double rowPrefixWidth;
  final int rowCount;
  final int measuresPerRow;
}

class NotationLayoutCalculator {
  const NotationLayoutCalculator();

  NotationLayout calculate({
    required List<Measure> measures,
    required int measuresPerRow,
    required double minMeasureWidth,
    required double rowHeight,
    required EdgeInsets padding,
    double rowPrefixWidth = 86,
    int partCount = 1,
  }) {
    final normalizedMeasuresPerRow = math.max(1, measuresPerRow);
    final longestRowCount = _longestRowCount(
      measures.length,
      normalizedMeasuresPerRow,
    );
    final width = padding.horizontal +
        rowPrefixWidth +
        longestRowCount * minMeasureWidth;

    final rowCount = measures.isEmpty
        ? 0
        : (measures.length / normalizedMeasuresPerRow).ceil();

    // Each system row stacks partCount staves vertically.
    final height = padding.vertical + (rowCount * partCount * rowHeight);

    return NotationLayout(
      size: Size(width, height),
      rowPrefixWidth: rowPrefixWidth,
      rowCount: rowCount,
      measuresPerRow: normalizedMeasuresPerRow,
    );
  }

  int _longestRowCount(int measureCount, int measuresPerRow) {
    if (measureCount <= 0) return 0;
    final fullRows = measureCount ~/ measuresPerRow;
    final remainder = measureCount % measuresPerRow;
    if (remainder == 0) return measuresPerRow;
    return fullRows == 0 ? remainder : math.max(measuresPerRow, remainder);
  }
}
