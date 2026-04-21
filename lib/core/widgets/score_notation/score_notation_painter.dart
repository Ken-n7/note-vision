import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/clef.dart';
import '../../models/key_signature.dart';
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';
import '../../models/time_signature.dart';
import 'staff_pitch_mapper.dart';

class ScoreNotationPainter extends CustomPainter {
  const ScoreNotationPainter({
    required this.parts,
    required this.measuresPerRow,
    required this.minMeasureWidth,
    required this.rowHeight,
    required this.padding,
    required this.rowPrefixWidth,
    this.selectedPartIndex,
    this.selectedMeasureIndex,
    this.selectedSymbolIndex,
    this.playbackPartIndex,
    this.playbackMeasureIndex,
    this.playbackSymbolIndex,
    this.dragFeedback,
    this.insertionTarget,
    this.insertionPreviewGlyph,
  });

  /// All parts — one inner list per part, each containing that part's measures.
  final List<List<Measure>> parts;
  final int measuresPerRow;
  final double minMeasureWidth;
  final double rowHeight;
  final EdgeInsets padding;
  final double rowPrefixWidth;
  final int? selectedPartIndex;
  final int? selectedMeasureIndex;
  final int? selectedSymbolIndex;

  /// Currently playing symbol position emitted by PlaybackService.
  /// All three must be non-null for the playback highlight to render.
  final int? playbackPartIndex;
  final int? playbackMeasureIndex;
  final int? playbackSymbolIndex;

  final NotationDragFeedback? dragFeedback;
  final NotationInsertTarget? insertionTarget;
  final NotationPreviewGlyph? insertionPreviewGlyph;

  static const double staffLineSpacing = 12;
  static const double tapTargetSize = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _buildRowMetrics();
    for (final row in metrics) {
      _drawRow(canvas, row);
    }
    if (parts.length > 1) _drawSystemConnectors(canvas, metrics);
  }

  List<_RowMetrics> _buildRowMetrics() {
    return _buildRowMetricsStatic(
      parts: parts,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
  }

  static Clef? _clefForRow(List<Measure> rowMeasures) {
    for (final m in rowMeasures) {
      if (m.clef != null) return m.clef;
    }
    return null;
  }

  /// Builds one [_RowMetrics] per (system, part) pair.
  /// Each system row stacks [parts.length] staves vertically, aligned by
  /// measure index — matching standard grand-staff notation layout.
  static List<_RowMetrics> _buildRowMetricsStatic({
    required List<List<Measure>> parts,
    required int measuresPerRow,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
    required double minMeasureWidth,
  }) {
    if (parts.isEmpty) return [];

    final partCount = parts.length;
    final maxMeasureCount = parts.fold(0, (m, p) => math.max(m, p.length));
    final systemCount = maxMeasureCount == 0
        ? 0
        : (maxMeasureCount / measuresPerRow).ceil();

    final rows = <_RowMetrics>[];

    for (var systemIndex = 0; systemIndex < systemCount; systemIndex++) {
      final systemStartMeasure = systemIndex * measuresPerRow;
      // Y origin for this system — each system occupies partCount * rowHeight.
      final systemTopY = padding.top + systemIndex * (partCount * rowHeight);

      for (var partIdx = 0; partIdx < partCount; partIdx++) {
        final partMeasures = parts[partIdx];
        if (systemStartMeasure >= partMeasures.length) continue;

        final rowEndExclusive = math.min(
          systemStartMeasure + measuresPerRow,
          partMeasures.length,
        );
        final rowMeasures = partMeasures.sublist(
          systemStartMeasure,
          rowEndExclusive,
        );

        final staffTop = systemTopY + partIdx * rowHeight + 28;
        final staffBottom = staffTop + staffLineSpacing * 4;
        final rowStartX = padding.left;
        final contentStartX = rowStartX + rowPrefixWidth;
        final rowEndX = contentStartX + (rowMeasures.length * minMeasureWidth);

        rows.add(
          _RowMetrics(
            rowIndex: systemIndex,
            partIndex: partIdx,
            globalStartMeasureIndex: systemStartMeasure,
            measures: rowMeasures,
            staffTop: staffTop,
            staffBottom: staffBottom,
            rowStartX: rowStartX,
            contentStartX: contentStartX,
            rowEndX: rowEndX,
            clef: _clefForRow(rowMeasures),
          ),
        );
      }
    }

    return rows;
  }

  static List<NotationSymbolTarget> buildSymbolTargets({
    required List<List<Measure>> parts,
    required int measuresPerRow,
    required double minMeasureWidth,
    required double rowHeight,
    required EdgeInsets padding,
    required double rowPrefixWidth,
  }) {
    final rows = _buildRowMetricsStatic(
      parts: parts,
      measuresPerRow: measuresPerRow,
      rowHeight: rowHeight,
      padding: padding,
      rowPrefixWidth: rowPrefixWidth,
      minMeasureWidth: minMeasureWidth,
    );
    final targets = <NotationSymbolTarget>[];

    for (final row in rows) {
      for (
        var measureInRow = 0;
        measureInRow < row.measures.length;
        measureInRow++
      ) {
        final measure = row.measures[measureInRow];
        final measureStartX =
            row.contentStartX + (measureInRow * minMeasureWidth);
        final measureEndX = measureStartX + minMeasureWidth;
        if (measure.symbols.isEmpty) continue;

        const innerPadding = 16.0;
        final drawableWidth = math.max(
          12.0,
          (measureEndX - measureStartX) - (innerPadding * 2),
        );

        for (
          var symbolIndex = 0;
          symbolIndex < measure.symbols.length;
          symbolIndex++
        ) {
          final symbol = measure.symbols[symbolIndex];
          final progress = (symbolIndex + 1) / (measure.symbols.length + 1);
          final x = measureStartX + innerPadding + (drawableWidth * progress);
          final y = _symbolCenterY(
            symbol,
            row.staffTop,
            row.staffBottom,
            row.clefSign,
            clefLine: row.clefLine,
          );
          targets.add(
            NotationSymbolTarget(
              partIndex: row.partIndex,
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

  static double _symbolCenterY(
    ScoreSymbol symbol,
    double staffTop,
    double staffBottom,
    String clefSign, {
    int clefLine = 2,
  }) {
    if (symbol is Note) {
      return StaffPitchMapper.yForPitch(
        step: symbol.step,
        octave: symbol.octave,
        bottomLineY: staffBottom,
        lineSpacing: staffLineSpacing,
        clefSign: clefSign,
        clefLine: clefLine,
      );
    }

    final restType = symbol is Rest ? symbol.type.trim().toLowerCase() : '';
    if (restType == 'whole') return staffTop + (staffLineSpacing * 3) + 4.3;
    if (restType == 'half') return staffTop + (staffLineSpacing * 2) - 3.0;
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

    switch (row.clefSign.toUpperCase()) {
      case 'F':
        _drawBassClef(canvas, x: row.rowStartX + 8, y: row.staffTop - 4);
      case 'C':
        _drawCClef(
          canvas,
          x: row.rowStartX + 6,
          y: row.staffTop,
          clefLine: row.clefLine,
        );
      default:
        _drawTrebleClef(canvas, x: row.rowStartX + 10, y: row.staffTop - 14);
    }

    _drawRowSignatures(canvas, row);

    for (var i = 0; i < 5; i++) {
      final y = row.staffTop + (i * staffLineSpacing);
      canvas.drawLine(
        Offset(row.rowStartX, y),
        Offset(row.rowEndX, y),
        linePaint,
      );
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
        clefSign: row.clefSign,
        clefLine: row.clefLine,
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

    for (
      var measureInRow = 0;
      measureInRow < row.measures.length;
      measureInRow++
    ) {
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
        partIndex: row.partIndex,
        absoluteMeasureIndex: row.globalStartMeasureIndex + measureInRow,
        measureStartX: measureX,
        measureEndX: nextMeasureX,
        staffTop: row.staffTop,
        staffBottom: row.staffBottom,
        clefSign: row.clefSign,
        clefLine: row.clefLine,
      );
    }
  }

  void _drawMeasureSymbols(
    Canvas canvas,
    Measure measure, {
    required int partIndex,
    required int absoluteMeasureIndex,
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    final middleLineY = staffTop + staffLineSpacing * 2;
    final insertTarget = insertionTarget;
    if (insertTarget != null &&
        insertTarget.measureIndex == absoluteMeasureIndex) {
      final linePaint = Paint()
        ..color = const Color(0xFF60A5FA)
        ..strokeWidth = 2.0;
      final x = insertTarget.indicatorX
          .clamp(measureStartX + 2, measureEndX - 2)
          .toDouble();
      canvas.drawLine(
        Offset(x, staffTop - 8),
        Offset(x, staffBottom + 8),
        linePaint,
      );
      final previewGlyph = insertionPreviewGlyph;
      if (previewGlyph != null) {
        _drawInsertionPreview(
          canvas,
          glyph: previewGlyph,
          x: x,
          target: insertTarget,
          staffTop: staffTop,
          staffBottom: staffBottom,
          middleLineY: middleLineY,
          clefSign: clefSign,
        );
      }
    }

    if (measure.symbols.isEmpty) return;

    final symbolCount = measure.symbols.length;
    const innerPadding = 16.0;
    final drawableWidth = math.max(
      12.0,
      (measureEndX - measureStartX) - (innerPadding * 2),
    );
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

    // Build beam groups before drawing so we know which notes suppress flags.
    final beamGroups = _buildBeamGroups(measure.symbols);
    final beamedIndices = <int>{};
    for (final group in beamGroups) {
      if (group.length >= 2) beamedIndices.addAll(group);
    }

    // Collect rendered (x, y) per symbol index for beam bar drawing.
    final notePositions = <int, Offset>{};

    for (var i = 0; i < symbolCount; i++) {
      if (activeDrag != null && i == activeDrag.draggedSymbolIndex) continue;
      final symbol = measure.symbols[i];
      var visualIndex = i;
      if (activeDrag != null) {
        final compactIndex = i > activeDrag.draggedSymbolIndex ? i - 1 : i;
        visualIndex = compactIndex >= activeDrag.targetSymbolIndex
            ? compactIndex + 1
            : compactIndex;
      }
      final progress = (visualIndex + 1) / (symbolCount + 1);
      final x = measureStartX + innerPadding + (drawableWidth * progress);

      if (symbol is Note) {
        final y = StaffPitchMapper.yForPitch(
          step: symbol.step,
          octave: symbol.octave,
          bottomLineY: staffBottom,
          lineSpacing: staffLineSpacing,
          clefSign: clefSign,
          clefLine: clefLine,
        );
        notePositions[i] = Offset(x, y);
        final isSelected =
            selectedPartIndex == partIndex &&
            selectedMeasureIndex == absoluteMeasureIndex &&
            selectedSymbolIndex == i;
        final isPlaying =
            playbackPartIndex == partIndex &&
            playbackMeasureIndex == absoluteMeasureIndex &&
            playbackSymbolIndex == i;
        if (isPlaying) _drawPlaybackHighlight(canvas, Offset(x, y));
        if (isSelected) _drawSelectionHighlight(canvas, Offset(x, y));
        _drawNote(
          canvas,
          symbol,
          x: x,
          y: y,
          middleLineY: middleLineY,
          suppressFlag: beamedIndices.contains(i),
        );
      } else if (symbol is Rest) {
        final y = _symbolCenterY(
          symbol,
          staffTop,
          staffBottom,
          clefSign,
          clefLine: clefLine,
        );
        final isSelected =
            selectedPartIndex == partIndex &&
            selectedMeasureIndex == absoluteMeasureIndex &&
            selectedSymbolIndex == i;
        final isPlaying =
            playbackPartIndex == partIndex &&
            playbackMeasureIndex == absoluteMeasureIndex &&
            playbackSymbolIndex == i;
        if (isPlaying) _drawPlaybackHighlight(canvas, Offset(x, y));
        if (isSelected) _drawSelectionHighlight(canvas, Offset(x, y));
        _drawRest(canvas, symbol, x: x, staffTop: staffTop);
      }
    }

    // Draw beam bars for groups of 2+.
    _drawBeamBars(canvas, beamGroups, notePositions, middleLineY);

    if (!hasDragInMeasure || draggedSymbol == null) return;

    final dragY =
        _symbolCenterY(
          draggedSymbol,
          staffTop,
          staffBottom,
          clefSign,
          clefLine: clefLine,
        ) -
        8;
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

  /// Groups consecutive beamed eighth notes by symbol index.
  static List<List<int>> _buildBeamGroups(List<ScoreSymbol> symbols) {
    final groups = <List<int>>[];
    List<int>? current;
    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      if (sym is Note && sym.type == 'eighth' && sym.beamed) {
        current ??= [];
        current.add(i);
      } else {
        if (current != null) {
          groups.add(current);
          current = null;
        }
      }
    }
    if (current != null) groups.add(current);
    return groups;
  }

  void _drawBeamBars(
    Canvas canvas,
    List<List<int>> beamGroups,
    Map<int, Offset> notePositions,
    double middleLineY,
  ) {
    final beamPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    const stemLen = staffLineSpacing * 3.4;
    const stemOffX = 6.0; // matches _drawStemAndFlag

    for (final group in beamGroups) {
      if (group.length < 2) continue;
      final firstPos = notePositions[group.first];
      final lastPos = notePositions[group.last];
      if (firstPos == null || lastPos == null) continue;

      final stemUp = firstPos.dy > middleLineY;
      final sign = stemUp ? -1.0 : 1.0;
      final xOff = stemUp ? stemOffX : -stemOffX;

      final x1 = firstPos.dx + xOff;
      final x2 = lastPos.dx + xOff;
      final y1 = firstPos.dy - sign * stemLen;
      final y2 = lastPos.dy - sign * stemLen;

      const beamThickness = 4.0;
      final top = math.min(y1, y2) - beamThickness / 2;
      canvas.drawRect(
        Rect.fromLTWH(x1, top, x2 - x1, beamThickness),
        beamPaint,
      );
    }
  }

  void _drawSelectionHighlight(
    Canvas canvas,
    Offset center, {
    double radius = 14,
  }) {
    final paint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.26)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
  }

  /// Playback highlight — a filled glow + outer ring in accent colour,
  /// visually distinct from the editor selection highlight.
  void _drawPlaybackHighlight(Canvas canvas, Offset center) {
    // Outer glow ring
    final ringPaint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 20, ringPaint);

    // Inner solid fill
    final fillPaint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 13, fillPaint);

    // Accent border
    final borderPaint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 13, borderPaint);
  }

  void _drawInsertionPreview(
    Canvas canvas, {
    required NotationPreviewGlyph glyph,
    required double x,
    required NotationInsertTarget target,
    required double staffTop,
    required double staffBottom,
    required double middleLineY,
    required String clefSign,
  }) {
    final previewPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.24)
      ..style = PaintingStyle.fill;
    final y = switch (glyph) {
      NotationPreviewGlyph.wholeRest => staffTop + (staffLineSpacing * 3) + 4.3,
      NotationPreviewGlyph.halfRest => staffTop + (staffLineSpacing * 2) - 3.0,
      NotationPreviewGlyph.quarterRest =>
        staffTop + (staffLineSpacing * 1.35) + 8.0,
      _ => StaffPitchMapper.yForPitch(
        step: target.step,
        octave: target.octave,
        bottomLineY: staffBottom,
        lineSpacing: staffLineSpacing,
        clefSign: clefSign,
      ),
    };
    _drawSelectionHighlight(canvas, Offset(x, y), radius: 15);
    canvas.drawCircle(Offset(x, y), 15, previewPaint);

    switch (glyph) {
      case NotationPreviewGlyph.wholeNote:
        _drawNote(
          canvas,
          const Note(step: 'B', octave: 4, duration: 8, type: 'whole'),
          x: x,
          y: y,
          middleLineY: middleLineY,
        );
      case NotationPreviewGlyph.halfNote:
        _drawNote(
          canvas,
          const Note(step: 'B', octave: 4, duration: 4, type: 'half'),
          x: x,
          y: y,
          middleLineY: middleLineY,
        );
      case NotationPreviewGlyph.quarterNote:
        _drawNote(
          canvas,
          const Note(step: 'B', octave: 4, duration: 2, type: 'quarter'),
          x: x,
          y: y,
          middleLineY: middleLineY,
        );
      case NotationPreviewGlyph.eighthNote:
        _drawNote(
          canvas,
          const Note(step: 'B', octave: 4, duration: 1, type: 'eighth'),
          x: x,
          y: y,
          middleLineY: middleLineY,
        );
      case NotationPreviewGlyph.wholeRest:
        _drawRest(
          canvas,
          const Rest(duration: 8, type: 'whole'),
          x: x,
          staffTop: staffTop,
        );
      case NotationPreviewGlyph.halfRest:
        _drawRest(
          canvas,
          const Rest(duration: 4, type: 'half'),
          x: x,
          staffTop: staffTop,
        );
      case NotationPreviewGlyph.quarterRest:
        _drawRest(
          canvas,
          const Rest(duration: 2, type: 'quarter'),
          x: x,
          staffTop: staffTop,
        );
    }
  }

  void _drawNote(
    Canvas canvas,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
    bool suppressFlag = false,
  }) {
    final normalizedType = note.type.trim().toLowerCase();
    final isWhole = normalizedType == 'whole';
    final isHalf = normalizedType == 'half';
    final isEighth =
        normalizedType == 'eighth' ||
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

    // Draw accidental to the left of the notehead.
    if (note.alter != null) {
      final accidentalText = switch (note.alter) {
        1 => '♯',
        -1 => '♭',
        0 => '♮',
        2 => '𝄪',
        -2 => '𝄫',
        _ => null,
      };
      if (accidentalText != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: accidentalText,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width - 3, y - tp.height * 0.6));
      }
    }

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
      drawFlag: isEighth && !suppressFlag,
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

  /// Draws a C clef (alto/tenor) centred on [clefLine] (1 = bottom staff line).
  void _drawCClef(
    Canvas canvas, {
    required double x,
    required double y,
    required int clefLine,
  }) {
    final fill = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final top = y;
    final bottom = y + staffLineSpacing * 4;
    // clefLine: 1 = bottom, 5 = top  →  Y decreases going up
    final targetY = y + (4 - (clefLine - 1)) * staffLineSpacing;

    // Left vertical bar (spine)
    canvas.drawRect(Rect.fromLTWH(x, top, 3.5, bottom - top), fill);

    // Upper bracket
    stroke.strokeWidth = 2.0;
    canvas.drawLine(Offset(x + 3.5, top), Offset(x + 14, top), stroke);
    stroke.strokeWidth = 1.5;
    canvas.drawLine(Offset(x + 14, top), Offset(x + 14, targetY), stroke);

    // Lower bracket
    stroke.strokeWidth = 2.0;
    canvas.drawLine(Offset(x + 3.5, bottom), Offset(x + 14, bottom), stroke);
    stroke.strokeWidth = 1.5;
    canvas.drawLine(Offset(x + 14, targetY), Offset(x + 14, bottom), stroke);

    // Centre line at the target staff line
    stroke.strokeWidth = 1.2;
    canvas.drawLine(Offset(x + 3.5, targetY), Offset(x + 12, targetY), stroke);
  }

  /// Draws a thin vertical line on the far left connecting all staves that
  /// belong to the same system (multi-part scores only).
  void _drawSystemConnectors(Canvas canvas, List<_RowMetrics> metrics) {
    // Group rows by systemIndex
    final Map<int, List<_RowMetrics>> systems = {};
    for (final row in metrics) {
      systems.putIfAbsent(row.rowIndex, () => []).add(row);
    }

    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;

    for (final rows in systems.values) {
      if (rows.length < 2) continue;
      rows.sort((a, b) => a.partIndex.compareTo(b.partIndex));
      final top = rows.first.staffTop;
      final bottom = rows.last.staffBottom;
      final x = rows.first.rowStartX;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  void _drawTrebleClef(Canvas canvas, {required double x, required double y}) {
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

  void _drawBassClef(Canvas canvas, {required double x, required double y}) {
    final inkPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    final cx = x + 10.0;
    final cy = y + staffLineSpacing * 1.5;

    final bodyPath = Path();
    bodyPath.moveTo(cx, cy - staffLineSpacing * 1.5);
    bodyPath.cubicTo(
      cx + 14,
      cy - staffLineSpacing * 1.5,
      cx + 18,
      cy - staffLineSpacing * 0.5,
      cx + 12,
      cy,
    );
    bodyPath.cubicTo(
      cx + 6,
      cy + staffLineSpacing * 0.5,
      cx - 2,
      cy + staffLineSpacing * 0.8,
      cx - 6,
      cy + staffLineSpacing * 2.0,
    );
    canvas.drawPath(bodyPath, inkPaint);

    final dotX = cx + 20.0;
    canvas.drawCircle(
      Offset(dotX, cy - staffLineSpacing * 0.6),
      2.5,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(dotX, cy + staffLineSpacing * 0.4),
      2.5,
      fillPaint,
    );
  }

  double _drawKeySignature(
    Canvas canvas,
    double x,
    KeySignature keySignature, {
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    final fifths = keySignature.fifths;
    if (fifths == 0) return x;

    final isSharp = fifths > 0;
    final count = fifths.abs().clamp(0, 7);
    final accidental = isSharp ? '#' : 'b';

    const sharpOrderTreble = [
      ('F', 5),
      ('C', 5),
      ('G', 5),
      ('D', 5),
      ('A', 4),
      ('E', 5),
      ('B', 4),
    ];
    const flatOrderTreble = [
      ('B', 4),
      ('E', 5),
      ('A', 4),
      ('D', 5),
      ('G', 4),
      ('C', 5),
      ('F', 4),
    ];
    const sharpOrderBass = [
      ('F', 3),
      ('C', 3),
      ('G', 3),
      ('D', 3),
      ('A', 2),
      ('E', 3),
      ('B', 2),
    ];
    const flatOrderBass = [
      ('B', 2),
      ('E', 3),
      ('A', 2),
      ('D', 3),
      ('G', 2),
      ('C', 3),
      ('F', 2),
    ];

    final isBass = clefSign.toUpperCase() == 'F';
    final order = isSharp
        ? (isBass ? sharpOrderBass : sharpOrderTreble)
        : (isBass ? flatOrderBass : flatOrderTreble);

    for (var i = 0; i < count; i++) {
      final pitch = order[i];
      final y = StaffPitchMapper.yForPitch(
        step: pitch.$1,
        octave: pitch.$2,
        bottomLineY: staffBottom,
        lineSpacing: staffLineSpacing,
        clefSign: clefSign,
        clefLine: clefLine,
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
    return oldDelegate.parts != parts ||
        oldDelegate.measuresPerRow != measuresPerRow ||
        oldDelegate.minMeasureWidth != minMeasureWidth ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.padding != padding ||
        oldDelegate.rowPrefixWidth != rowPrefixWidth ||
        oldDelegate.selectedPartIndex != selectedPartIndex ||
        oldDelegate.selectedMeasureIndex != selectedMeasureIndex ||
        oldDelegate.selectedSymbolIndex != selectedSymbolIndex ||
        oldDelegate.playbackPartIndex != playbackPartIndex ||
        oldDelegate.playbackMeasureIndex != playbackMeasureIndex ||
        oldDelegate.playbackSymbolIndex != playbackSymbolIndex ||
        oldDelegate.dragFeedback != dragFeedback ||
        oldDelegate.insertionTarget != insertionTarget ||
        oldDelegate.insertionPreviewGlyph != insertionPreviewGlyph;
  }
}

enum NotationPreviewGlyph {
  wholeNote,
  halfNote,
  quarterNote,
  eighthNote,
  wholeRest,
  halfRest,
  quarterRest,
}

class NotationSymbolTarget {
  const NotationSymbolTarget({
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
    required this.center,
    required this.hitRect,
  });

  final int partIndex;
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

class NotationInsertTarget {
  const NotationInsertTarget({
    this.partIndex = 0,
    required this.measureIndex,
    required this.insertIndex,
    required this.indicatorX,
    required this.step,
    required this.octave,
  });

  final int partIndex;
  final int measureIndex;
  final int insertIndex;
  final double indicatorX;
  final String step;
  final int octave;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotationInsertTarget &&
        other.partIndex == partIndex &&
        other.measureIndex == measureIndex &&
        other.insertIndex == insertIndex &&
        other.indicatorX == indicatorX &&
        other.step == step &&
        other.octave == octave;
  }

  @override
  int get hashCode =>
      partIndex.hashCode ^
      measureIndex.hashCode ^
      insertIndex.hashCode ^
      indicatorX.hashCode ^
      step.hashCode ^
      octave.hashCode;
}

class _RowMetrics {
  const _RowMetrics({
    required this.rowIndex,
    required this.partIndex,
    required this.globalStartMeasureIndex,
    required this.measures,
    required this.staffTop,
    required this.staffBottom,
    required this.rowStartX,
    required this.contentStartX,
    required this.rowEndX,
    required this.clef,
  });

  final int rowIndex;
  final int partIndex;
  final int globalStartMeasureIndex;
  final List<Measure> measures;
  final double staffTop;
  final double staffBottom;
  final double rowStartX;
  final double contentStartX;
  final double rowEndX;
  final Clef? clef;

  String get clefSign => clef?.sign ?? 'G';
  int get clefLine => clef?.line ?? 2;
}
