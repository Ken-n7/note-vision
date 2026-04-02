import '../../models/measure.dart';
import 'package:flutter/material.dart';

class NotationSymbolTarget {
  const NotationSymbolTarget({
    required this.measureIndex,
    required this.symbolIndex,
    required this.center,
    required this.hitRect,
  });

  final int measureIndex;
  final int symbolIndex;
  final Offset center;
  final Rect hitRect;
}

class NotationDragFeedback {
  const NotationDragFeedback({
    required this.measureIndex,
    required this.draggedSymbolIndex,
    required this.targetSymbolIndex,
    required this.dragX,
  });

  final int measureIndex;
  final int draggedSymbolIndex;
  final int targetSymbolIndex;
  final double dragX;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotationDragFeedback &&
          runtimeType == other.runtimeType &&
          measureIndex == other.measureIndex &&
          draggedSymbolIndex == other.draggedSymbolIndex &&
          targetSymbolIndex == other.targetSymbolIndex &&
          dragX == other.dragX;

  @override
  int get hashCode =>
      measureIndex.hashCode ^
      draggedSymbolIndex.hashCode ^
      targetSymbolIndex.hashCode ^
      dragX.hashCode;
}

class RowMetrics {
  const RowMetrics({
    required this.rowIndex,
    required this.globalStartMeasureIndex,
    required this.measures,
    required this.staffTop,
    required this.staffBottom,
    required this.rowStartX,
    required this.contentStartX,
    required this.rowEndX,
  });

  final int rowIndex;
  final int globalStartMeasureIndex;
  final List<Measure> measures;
  final double staffTop;
  final double staffBottom;
  final double rowStartX;
  final double contentStartX;
  final double rowEndX;
}
