import 'dart:math' as math;

import 'package:flutter/material.dart';

export 'score_notation_layout_models.dart';
import '../../models/key_signature.dart';
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';
import '../../models/time_signature.dart';
import 'notation_glyph_painter.dart';
import 'score_notation_layout_models.dart';
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

  static const double staffLineSpacing = 12;
  static const double tapTargetSize = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _buildRowMetrics();
    for (final row in metrics) {
      _drawRow(canvas, row);
    }
  }

  List<RowMetrics> _buildRowMetrics() {
    return _buildRowMetricsStatic(
      measures: measures,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
  }

  static List<RowMetrics> _buildRowMetricsStatic({
    required List<Measure> measures,
    required int measuresPerRow,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
    required double minMeasureWidth,
  }) {
    final rows = <RowMetrics>[];
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
        RowMetrics(
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
          final y = NotationGlyphPainter.symbolCenterY(symbol: symbol, staffTop: row.staffTop, staffBottom: row.staffBottom, staffLineSpacing: staffLineSpacing);
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


  void _drawRow(Canvas canvas, RowMetrics row) {
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

  void _drawRowSignatures(Canvas canvas, RowMetrics row) {
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

  void _drawMeasures(Canvas canvas, RowMetrics row, Paint barPaint) {
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
    }
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
          NotationGlyphPainter.drawSelectionHighlight(canvas, Offset(x, y));
        }
        NotationGlyphPainter.drawNote(canvas, symbol, x: x, y: y, middleLineY: middleLineY, staffLineSpacing: staffLineSpacing);
      } else if (symbol is Rest) {
        final y = NotationGlyphPainter.symbolCenterY(symbol: symbol, staffTop: staffTop, staffBottom: staffBottom, staffLineSpacing: staffLineSpacing);
        final isSelected =
            selectedMeasureIndex == absoluteMeasureIndex &&
            selectedSymbolIndex == i;
        if (isSelected) {
          NotationGlyphPainter.drawSelectionHighlight(canvas, Offset(x, y));
        }
        NotationGlyphPainter.drawRest(canvas, symbol, x: x, staffTop: staffTop, staffLineSpacing: staffLineSpacing);
      }
    }

    if (!hasDragInMeasure || draggedSymbol == null) return;

    final dragY = NotationGlyphPainter.symbolCenterY(symbol: draggedSymbol, staffTop: staffTop, staffBottom: staffBottom, staffLineSpacing: staffLineSpacing) - 8;
    if (draggedSymbol is Note) {
      NotationGlyphPainter.drawSelectionHighlight(canvas, Offset(clampedDragX, dragY), radius: 16);
      NotationGlyphPainter.drawNote(
        canvas,
        draggedSymbol,
        x: clampedDragX,
        y: dragY,
        middleLineY: middleLineY,
        staffLineSpacing: staffLineSpacing,
      );
    } else if (draggedSymbol is Rest) {
      NotationGlyphPainter.drawSelectionHighlight(canvas, Offset(clampedDragX, dragY), radius: 16);
      NotationGlyphPainter.drawRest(canvas, draggedSymbol, x: clampedDragX, staffTop: staffTop - 8, staffLineSpacing: staffLineSpacing);
    }
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
        oldDelegate.dragFeedback != dragFeedback;
  }
}
