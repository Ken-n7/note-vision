import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/key_signature.dart';
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';
import '../../models/time_signature.dart';
import 'staff_pitch_mapper.dart';

class ScoreNotationPainter extends CustomPainter {
  const ScoreNotationPainter({
    required this.measures,
    required this.measuresPerRow,
    required this.minMeasureWidth,
    required this.rowHeight,
    required this.padding,
    required this.rowPrefixWidth,
    this.selectedMeasureIndex,
    this.selectedSymbolIndex,
    this.dragFeedback,
    this.insertionIndicator,
  });

  final List<Measure> measures;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final double rowPrefixWidth;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;
  final NotationDragFeedback? dragFeedback;
  final NotationInsertionIndicator? insertionIndicator;

  static const double staffLineSpacing = 12;
  static const double tapTargetSize = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _buildRowMetrics();
    for (final row in metrics) {
      _drawRow(canvas, row);
    }
  }

  List<_RowMetrics> _buildRowMetrics() {
    return _buildRowMetricsStatic(
      measures: measures,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
  }

  static List<_RowMetrics> _buildRowMetricsStatic({
    required List<Measure> measures,
    required int measuresPerRow,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
    required double minMeasureWidth,
  }) {
    final rows = <_RowMetrics>[];
    final rowCount = (measures.length / measuresPerRow).ceil();

    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
      final rowStartMeasure = rowIndex * measuresPerRow;
      final rowEndExclusive = math.min(rowStartMeasure + measuresPerRow, measures.length);
      final rowMeasures = measures.sublist(rowStartMeasure, rowEndExclusive);
      final rowTop = padding.top + rowIndex * rowHeight + 28;
      final staffTop = rowTop;
      final staffBottom = staffTop + staffLineSpacing * 4;
      final rowStartX = padding.left;
      final contentStartX = rowStartX + rowPrefixWidth;
      final rowEndX = contentStartX + (rowMeasures.length * minMeasureWidth);

      rows.add(
        _RowMetrics(
          rowIndex: rowIndex,
          globalStartMeasureIndex: rowStartMeasure,
          measures: rowMeasures,
          staffTop: staffTop,
          staffBottom: staffBottom,
          rowStartX: rowStartX,
          contentStartX: contentStartX,
          rowEndX: rowEndX,
        ),
      );
    }

    return rows;
  }

  static List<NotationSymbolTarget> buildSymbolTargets({
    required List<Measure> measures,
    required int measuresPerRow,
    required double minMeasureWidth,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
  }) {
    final rows = _buildRowMetricsStatic(
      measures: measures,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
    final targets = <NotationSymbolTarget>[];

    for (final row in rows) {
      for (var measureInRow = 0; measureInRow < row.measures.length; measureInRow++) {
        final measure = row.measures[measureInRow];
        final measureStartX = row.contentStartX + (measureInRow * minMeasureWidth);
        final measureEndX = measureStartX + minMeasureWidth;
        if (measure.symbols.isEmpty) continue;

        const innerPadding = 16.0;
        final drawableWidth = math.max(
          12.0,
          (measureEndX - measureStartX) - (innerPadding * 2),
        );

        for (var symbolIndex = 0; symbolIndex < measure.symbols.length; symbolIndex++) {
          final symbol = measure.symbols[symbolIndex];
          final progress = (symbolIndex + 1) / (measure.symbols.length + 1);
          final x = measureStartX + innerPadding + (drawableWidth * progress);
          final y = _symbolCenterY(symbol, row.staffTop, row.staffBottom);
          targets.add(
            NotationSymbolTarget(
              measureIndex: row.globalStartMeasureIndex + measureInRow,
              symbolIndex: symbolIndex,
              center: Offset(x, y),
              hitRect: Rect.fromCenter(
                center: Offset(x, y),
                width: tapTargetSize,
                height: tapTargetSize,
              ),
            ),
          );
        }
      }
    }
    return targets;
  }

  static List<NotationMeasureTarget> buildMeasureTargets({
    required List<Measure> measures,
    required int measuresPerRow,
    required double minMeasureWidth,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
  }) {
    final rows = _buildRowMetricsStatic(
      measures: measures,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
    final targets = <NotationMeasureTarget>[];
    for (final row in rows) {
      for (var measureInRow = 0; measureInRow < row.measures.length; measureInRow++) {
        final measure = row.measures[measureInRow];
        final measureStartX = row.contentStartX + (measureInRow * minMeasureWidth);
        final measureEndX = measureStartX + minMeasureWidth;
        targets.add(
          NotationMeasureTarget(
            measureIndex: row.globalStartMeasureIndex + measureInRow,
            measureRect: Rect.fromLTRB(
              measureStartX,
              row.staffTop,
              measureEndX,
              row.staffBottom,
            ),
            lineYs: List<double>.generate(
              5,
              (index) => row.staffTop + (index * staffLineSpacing),
              growable: false,
            ),
            symbolCentersX: _symbolCentersX(
              measure,
              measureStartX: measureStartX,
              measureEndX: measureEndX,
            ),
            innerStartX: measureStartX + 16,
            innerEndX: measureEndX - 16,
          ),
        );
      }
    }
    return targets;
  }

  static double _symbolCenterY(ScoreSymbol symbol, double staffTop, double staffBottom) {
    if (symbol is Note) {
      return StaffPitchMapper.yForPitch(
        step: symbol.step,
        octave: symbol.octave,
        bottomLineY: staffBottom,
        lineSpacing: staffLineSpacing,
      );
    }

    final restType = symbol is Rest ? symbol.type.trim().toLowerCase() : '';
    if (restType == 'whole') {
      return staffTop + (staffLineSpacing * 3) + 4.3;
    }
    if (restType == 'half') {
      return staffTop + (staffLineSpacing * 2) - 3.0;
    }
    return staffTop + (staffLineSpacing * 1.35) + 8.0;
  }

  void _drawRow(Canvas canvas, _RowMetrics row) {
    final linePaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final thinBarPaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 1.2;

    _drawTrebleClef(canvas, x: row.rowStartX + 10, y: row.staffTop - 14);
    _drawRowSignatures(canvas, row);

    for (var i = 0; i < 5; i++) {
      final y = row.staffTop + (i * staffLineSpacing);
      canvas.drawLine(Offset(row.rowStartX, y), Offset(row.rowEndX, y), linePaint);
    }

    canvas.drawLine(
      Offset(row.contentStartX, row.staffTop),
      Offset(row.contentStartX, row.staffBottom),
      thinBarPaint,
    );
    canvas.drawLine(
      Offset(row.rowEndX, row.staffTop),
      Offset(row.rowEndX, row.staffBottom),
      thinBarPaint,
    );

    _drawMeasures(canvas, row, thinBarPaint);
  }

  void _drawRowSignatures(Canvas canvas, _RowMetrics row) {
    if (row.rowIndex != 0 || row.measures.isEmpty) return;

    final firstMeasure = row.measures.first;
    final timeSig = firstMeasure.timeSignature;
    final keySig = firstMeasure.keySignature;
    var signatureX = row.rowStartX + 42;

    if (keySig != null) {
      signatureX = _drawKeySignature(
        canvas,
        signatureX,
        keySig,
        staffBottom: row.staffBottom,
      );
    }

    if (timeSig != null) {
      _drawTimeSignature(
        canvas,
        x: signatureX + 10,
        y: row.staffTop - 2,
        signature: timeSig,
      );
    }
  }

  void _drawMeasures(Canvas canvas, _RowMetrics row, Paint barPaint) {
    const measureNumberStyle = TextStyle(
      color: Color(0xFF374151),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    for (var measureInRow = 0; measureInRow < row.measures.length; measureInRow++) {
      final measure = row.measures[measureInRow];
      final measureX = row.contentStartX + (measureInRow * minMeasureWidth);
      final nextMeasureX = measureX + minMeasureWidth;

      _drawMeasureNumber(
        canvas,
        text: '${measure.number}',
        x: measureX + 8,
        y: row.staffTop - 22,
        style: measureNumberStyle,
      );

      if (measureInRow > 0) {
        canvas.drawLine(
          Offset(measureX, row.staffTop),
          Offset(measureX, row.staffBottom),
          barPaint,
        );
      }

      _drawMeasureSymbols(
        canvas,
        measure,
        absoluteMeasureIndex: row.globalStartMeasureIndex + measureInRow,
        measureStartX: measureX,
        measureEndX: nextMeasureX,
        staffTop: row.staffTop,
        staffBottom: row.staffBottom,
      );

      final indicator = insertionIndicator;
      if (indicator != null &&
          indicator.measureIndex == row.globalStartMeasureIndex + measureInRow) {
        final indicatorX = _insertionLineX(
          symbolCentersX: _symbolCentersX(
            measure,
            measureStartX: measureX,
            measureEndX: nextMeasureX,
          ),
          insertIndex: indicator.insertIndex,
          measureStartX: measureX,
          measureEndX: nextMeasureX,
        );
        final paint = Paint()
          ..color = const Color(0xFF3B82F6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(indicatorX, row.staffTop - 8),
          Offset(indicatorX, row.staffBottom + 8),
          paint,
        );
      }
    }
  }

  static List<double> _symbolCentersX(
    Measure measure, {
    required double measureStartX,
    required double measureEndX,
  }) {
    if (measure.symbols.isEmpty) return const [];
    const innerPadding = 16.0;
    final drawableWidth = math.max(
      12.0,
      (measureEndX - measureStartX) - (innerPadding * 2),
    );
    return List<double>.generate(measure.symbols.length, (symbolIndex) {
      final progress = (symbolIndex + 1) / (measure.symbols.length + 1);
      return measureStartX + innerPadding + (drawableWidth * progress);
    }, growable: false);
  }

  static double _insertionLineX({
    required List<double> symbolCentersX,
    required int insertIndex,
    required double measureStartX,
    required double measureEndX,
  }) {
    const innerPadding = 16.0;
    final clampedIndex = insertIndex.clamp(0, symbolCentersX.length);
    final innerStart = measureStartX + innerPadding;
    final innerEnd = measureEndX - innerPadding;
    if (symbolCentersX.isEmpty) {
      return (innerStart + innerEnd) / 2;
    }
    if (clampedIndex == 0) return (innerStart + symbolCentersX.first) / 2;
    if (clampedIndex == symbolCentersX.length) {
      return (symbolCentersX.last + innerEnd) / 2;
    }
    return (symbolCentersX[clampedIndex - 1] + symbolCentersX[clampedIndex]) / 2;
  }

  void _drawMeasureSymbols(
    Canvas canvas,
    Measure measure, {
    required int absoluteMeasureIndex,
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
  }) {
    if (measure.symbols.isEmpty) return;

    final symbolCount = measure.symbols.length;
    const innerPadding = 16.0;
    final drawableWidth = math.max(
      12.0,
      (measureEndX - measureStartX) - (innerPadding * 2),
    );
    final middleLineY = staffTop + staffLineSpacing * 2;
    final drag = dragFeedback;
    final hasDragInMeasure =
        drag != null &&
        drag.measureIndex == absoluteMeasureIndex &&
        drag.draggedSymbolIndex >= 0 &&
        drag.draggedSymbolIndex < symbolCount &&
        drag.targetSymbolIndex >= 0 &&
        drag.targetSymbolIndex < symbolCount;
    final activeDrag = hasDragInMeasure ? drag : null;
    final draggedSymbol = activeDrag != null
        ? measure.symbols[activeDrag.draggedSymbolIndex]
        : null;
    final clampedDragX = activeDrag != null
        ? activeDrag.dragX.clamp(
            measureStartX + innerPadding,
            measureEndX - innerPadding,
          )
        : 0.0;

    for (var i = 0; i < symbolCount; i++) {
      if (activeDrag != null && i == activeDrag.draggedSymbolIndex) {
        continue;
      }
      final symbol = measure.symbols[i];
      var visualIndex = i;
      if (activeDrag != null) {
        final compactIndex = i > activeDrag.draggedSymbolIndex ? i - 1 : i;
        visualIndex =
            compactIndex >= activeDrag.targetSymbolIndex ? compactIndex + 1 : compactIndex;
      }
      final progress = (visualIndex + 1) / (symbolCount + 1);
      final x = measureStartX + innerPadding + (drawableWidth * progress);

      if (symbol is Note) {
        final y = StaffPitchMapper.yForPitch(
          step: symbol.step,
          octave: symbol.octave,
          bottomLineY: staffBottom,
          lineSpacing: staffLineSpacing,
        );
        final isSelected =
            selectedMeasureIndex == absoluteMeasureIndex &&
            selectedSymbolIndex == i;
        if (isSelected) {
          _drawSelectionHighlight(canvas, Offset(x, y));
        }
        _drawNote(canvas, symbol, x: x, y: y, middleLineY: middleLineY);
      } else if (symbol is Rest) {
        final y = _symbolCenterY(symbol, staffTop, staffBottom);
        final isSelected =
            selectedMeasureIndex == absoluteMeasureIndex &&
            selectedSymbolIndex == i;
        if (isSelected) {
          _drawSelectionHighlight(canvas, Offset(x, y));
        }
        _drawRest(canvas, symbol, x: x, staffTop: staffTop);
      }
    }

    if (!hasDragInMeasure || draggedSymbol == null) return;

    final dragY = _symbolCenterY(draggedSymbol, staffTop, staffBottom) - 8;
    if (draggedSymbol is Note) {
      _drawSelectionHighlight(canvas, Offset(clampedDragX, dragY), radius: 16);
      _drawNote(
        canvas,
        draggedSymbol,
        x: clampedDragX,
        y: dragY,
        middleLineY: middleLineY,
      );
    } else if (draggedSymbol is Rest) {
      _drawSelectionHighlight(canvas, Offset(clampedDragX, dragY), radius: 16);
      _drawRest(canvas, draggedSymbol, x: clampedDragX, staffTop: staffTop - 8);
    }
  }

  void _drawSelectionHighlight(Canvas canvas, Offset center, {double radius = 14}) {
    final paint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.26)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
  }

  void _drawNote(
    Canvas canvas,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
  }) {
    final normalizedType = note.type.trim().toLowerCase();
    final isWhole = normalizedType == 'whole';
    final isHalf = normalizedType == 'half';
    final isEighth = normalizedType == 'eighth' ||
        normalizedType == 'flag8thup' ||
        normalizedType == 'flag8thdown';

    final headWidth = isWhole ? 14.0 : 12.5;
    final headHeight = isWhole ? 9.8 : 8.8;

    final fillPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.35);
    final noteRect = Rect.fromCenter(
      center: Offset.zero,
      width: headWidth,
      height: headHeight,
    );
    if (isWhole || isHalf) {
      canvas.drawOval(noteRect, strokePaint);
    } else {
      canvas.drawOval(noteRect, fillPaint);
    }
    canvas.restore();

    if (isWhole) return;

    final stemUp = y > middleLineY;
    _drawStemAndFlag(
      canvas,
      x: x,
      y: y,
      stemUp: stemUp,
      drawFlag: isEighth,
    );
  }

  void _drawStemAndFlag(
    Canvas canvas, {
    required double x,
    required double y,
    required bool stemUp,
    required bool drawFlag,
  }) {
    final stemPaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 1.3;

    final stemLength = staffLineSpacing * 3.4;
    final stemX = stemUp ? x + 6 : x - 6;
    final endY = stemUp ? y - stemLength : y + stemLength;

    canvas.drawLine(Offset(stemX, y), Offset(stemX, endY), stemPaint);

    if (!drawFlag) return;

    final path = Path();
    if (stemUp) {
      path.moveTo(stemX, endY + 0.5);
      path.quadraticBezierTo(stemX + 10, endY + 2, stemX + 6, endY + 12);
      path.quadraticBezierTo(stemX + 8, endY + 8, stemX + 1, endY + 6);
    } else {
      path.moveTo(stemX, endY - 0.5);
      path.quadraticBezierTo(stemX - 10, endY - 2, stemX - 6, endY - 12);
      path.quadraticBezierTo(stemX - 8, endY - 8, stemX - 1, endY - 6);
    }

    final flagPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, flagPaint);
  }

  void _drawRest(
    Canvas canvas,
    Rest rest, {
    required double x,
    required double staffTop,
  }) {
    final type = rest.type.trim().toLowerCase();
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    if (type == 'whole') {
      final line4Y = staffTop + (staffLineSpacing * 3);
      final rect = Rect.fromCenter(
        center: Offset(x, line4Y + 4.3),
        width: 16,
        height: 4.8,
      );
      canvas.drawRect(rect, paint);
      return;
    }

    if (type == 'half') {
      final line3Y = staffTop + (staffLineSpacing * 2);
      final rect = Rect.fromCenter(
        center: Offset(x, line3Y - 3.0),
        width: 16,
        height: 4.8,
      );
      canvas.drawRect(rect, paint);
      return;
    }

    final y = staffTop + (staffLineSpacing * 1.35);
    final path = Path()
      ..moveTo(x - 3, y - 5)
      ..lineTo(x + 3, y - 1)
      ..lineTo(x - 2, y + 4)
      ..lineTo(x + 3, y + 9)
      ..lineTo(x - 1, y + 14)
      ..lineTo(x + 3, y + 19)
      ..lineTo(x - 4, y + 22)
      ..lineTo(x - 1, y + 16)
      ..lineTo(x - 6, y + 11)
      ..lineTo(x - 1, y + 5)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawMeasureNumber(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required TextStyle style,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset(x, y));
  }

  void _drawTrebleClef(
    Canvas canvas, {
    required double x,
    required double y,
  }) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontSize: 42,
          color: Color(0xFF111827),
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset(x, y));
  }

  double _drawKeySignature(
    Canvas canvas,
    double x,
    KeySignature keySignature, {
    required double staffBottom,
  }) {
    final fifths = keySignature.fifths;
    if (fifths == 0) return x;

    final isSharp = fifths > 0;
    final count = fifths.abs().clamp(0, 7);
    final accidental = isSharp ? '#' : 'b';

    const sharpOrder = [
      ('F', 5),
      ('C', 5),
      ('G', 5),
      ('D', 5),
      ('A', 4),
      ('E', 5),
      ('B', 4),
    ];

    const flatOrder = [
      ('B', 4),
      ('E', 5),
      ('A', 4),
      ('D', 5),
      ('G', 4),
      ('C', 5),
      ('F', 4),
    ];

    final order = isSharp ? sharpOrder : flatOrder;

    for (var i = 0; i < count; i++) {
      final pitch = order[i];
      final y = StaffPitchMapper.yForPitch(
        step: pitch.$1,
        octave: pitch.$2,
        bottomLineY: staffBottom,
        lineSpacing: staffLineSpacing,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: accidental,
          style: const TextStyle(
            fontSize: 20,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x, y - 12));
      x += 10;
    }

    return x;
  }

  void _drawTimeSignature(
    Canvas canvas, {
    required double x,
    required double y,
    required TimeSignature signature,
  }) {
    final top = TextPainter(
      text: TextSpan(
        text: '${signature.beats}',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bottom = TextPainter(
      text: TextSpan(
        text: '${signature.beatType}',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    top.paint(canvas, Offset(x, y));
    bottom.paint(canvas, Offset(x, y + staffLineSpacing * 2));
  }

  @override
  bool shouldRepaint(covariant ScoreNotationPainter oldDelegate) {
    return oldDelegate.measures != measures ||
        oldDelegate.measuresPerRow != measuresPerRow ||
        oldDelegate.minMeasureWidth != minMeasureWidth ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.padding != padding ||
        oldDelegate.rowPrefixWidth != rowPrefixWidth ||
        oldDelegate.selectedMeasureIndex != selectedMeasureIndex ||
        oldDelegate.selectedSymbolIndex != selectedSymbolIndex ||
        oldDelegate.dragFeedback != dragFeedback ||
        oldDelegate.insertionIndicator != insertionIndicator;
  }
}

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

class NotationInsertionIndicator {
  const NotationInsertionIndicator({
    required this.measureIndex,
    required this.insertIndex,
  });

  final int measureIndex;
  final int insertIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotationInsertionIndicator &&
          runtimeType == other.runtimeType &&
          measureIndex == other.measureIndex &&
          insertIndex == other.insertIndex;

  @override
  int get hashCode => measureIndex.hashCode ^ insertIndex.hashCode;
}

class NotationMeasureTarget {
  const NotationMeasureTarget({
    required this.measureIndex,
    required this.measureRect,
    required this.lineYs,
    required this.symbolCentersX,
    required this.innerStartX,
    required this.innerEndX,
  });

  final int measureIndex;
  final Rect measureRect;
  final List<double> lineYs;
  final List<double> symbolCentersX;
  final double innerStartX;
  final double innerEndX;
}

class _RowMetrics {
  const _RowMetrics({
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
