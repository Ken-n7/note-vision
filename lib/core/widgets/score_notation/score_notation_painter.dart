import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/clef.dart';
import '../../models/key_signature.dart';
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';
import '../../models/time_signature.dart';
import 'score_notation_metrics.dart';
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
    this.playbackNextPartIndex,
    this.playbackNextMeasureIndex,
    this.playbackNextSymbolIndex,
    this.playheadPartIndex,
    this.playheadMeasureIndex,
    this.playheadSymbolIndex,
    this.playbackProgress = 0,
    this.showPlaybackSymbolHighlight = true,
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
  final int? playbackNextPartIndex;
  final int? playbackNextMeasureIndex;
  final int? playbackNextSymbolIndex;
  final int? playheadPartIndex;
  final int? playheadMeasureIndex;
  /// Index of the symbol within its measure that the playhead is on.
  final int? playheadSymbolIndex;
  /// 0→1 fractional progress within the current note (from AnimationController).
  final double playbackProgress;
  final bool showPlaybackSymbolHighlight;

  final NotationDragFeedback? dragFeedback;
  final NotationInsertTarget? insertionTarget;
  final NotationPreviewGlyph? insertionPreviewGlyph;

  static const double staffLineSpacing = ScoreNotationMetrics.staffLineSpacing;
  static const double tapTargetSize = ScoreNotationMetrics.tapTargetSize;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _buildRowMetrics();
    for (final row in metrics) {
      _drawRow(canvas, row);
    }
    if (parts.length > 1) _drawSystemConnectors(canvas, metrics);
    _drawPlaybackPlayhead(canvas, metrics);
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
        final staffBottom =
            staffTop + ScoreNotationMetrics.staffHeightFor(staffLineSpacing);
        final rowStartX = padding.left;
        final contentStartX = rowStartX + rowPrefixWidth;
        final rowEndX = contentStartX + (rowMeasures.length * minMeasureWidth);
        final timeInMeasure = [
          for (var i = 0; i < rowMeasures.length; i++)
            ScoreNotationMetrics.timeSignatureInMeasure(
              partMeasures,
              systemStartMeasure + i,
              measureInRow: i,
              rowPrefixWidth: rowPrefixWidth,
            ),
        ];

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
            timeInPrefix:
                ScoreNotationMetrics.showsTimeSignature(
                  partMeasures,
                  systemStartMeasure,
                ) &&
                !timeInMeasure.first,
            timeInMeasure: timeInMeasure,
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

        final inset = row.laneInset(measureInRow);
        final drawableWidth = math.max(
          12.0,
          (measureEndX - measureStartX) -
              inset -
              ScoreNotationMetrics.measureInnerPadding,
        );

        for (
          var symbolIndex = 0;
          symbolIndex < measure.symbols.length;
          symbolIndex++
        ) {
          final symbol = measure.symbols[symbolIndex];
          if (symbol is Note && symbol.isChordTone) {
            continue;
          }
          final visualSlot = _visualSlotForIndex(measure.symbols, symbolIndex);
          final slotCount = _visualSlotCount(measure.symbols);
          final progress = (visualSlot + 1) / (slotCount + 1);
          final x = measureStartX + inset + (drawableWidth * progress);
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
    if (restType == 'whole') {
      return staffTop +
          (staffLineSpacing * ScoreNotationMetrics.wholeRestLineIndex) +
          ScoreNotationMetrics.wholeRestCenterYOffset;
    }
    if (restType == 'half') {
      return staffTop +
          (staffLineSpacing * ScoreNotationMetrics.halfRestLineIndex) +
          ScoreNotationMetrics.halfRestCenterYOffset;
    }
    return staffTop +
        (staffLineSpacing * ScoreNotationMetrics.quarterRestLineIndex) +
        ScoreNotationMetrics.quarterRestCenterYOffset;
  }

  void _drawRow(Canvas canvas, _RowMetrics row) {
    final linePaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = ScoreNotationMetrics.staffLineStrokeWidth
      ..style = PaintingStyle.stroke;

    final thinBarPaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = ScoreNotationMetrics.barlineStrokeWidth;

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
        _drawTrebleClef(
          canvas,
          x: row.rowStartX + ScoreNotationMetrics.trebleClefXOffset,
          y: ScoreNotationMetrics.trebleClefTopForStaff(
            staffTop: row.staffTop,
            lineSpacing: staffLineSpacing,
          ),
        );
    }

    _drawRowSignatures(canvas, row);

    for (var i = 0; i < ScoreNotationMetrics.staffLineCount; i++) {
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

  /// The key signature starts every row, as in the PDF; the time signature
  /// only the page's first row and a row that changes it.
  void _drawRowSignatures(Canvas canvas, _RowMetrics row) {
    if (row.measures.isEmpty) return;

    final firstMeasure = row.measures.first;
    final timeSig = firstMeasure.timeSignature;
    final keySig = firstMeasure.keySignature;
    var signatureX = row.rowStartX + ScoreNotationMetrics.rowSignatureStartX;

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

    if (timeSig != null && row.timeInPrefix) {
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
      fontSize: ScoreNotationMetrics.measureNumberFontSize,
      fontFamily: ScoreNotationMetrics.textFontFamily,
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
        x: measureX + ScoreNotationMetrics.measureNumberOffsetX,
        y: row.staffTop + ScoreNotationMetrics.measureNumberOffsetY,
        style: measureNumberStyle,
      );

      if (measureInRow > 0) {
        canvas.drawLine(
          Offset(measureX, row.staffTop),
          Offset(measureX, row.staffBottom),
          barPaint,
        );
      }

      if (row.timeInMeasure[measureInRow]) {
        _drawTimeSignature(
          canvas,
          x: measureX + ScoreNotationMetrics.timeSignatureInMeasureX,
          y: row.staffTop - 2,
          signature: measure.timeSignature!,
        );
      }

      _drawMeasureSymbols(
        canvas,
        measure,
        partIndex: row.partIndex,
        absoluteMeasureIndex: row.globalStartMeasureIndex + measureInRow,
        laneInset: row.laneInset(measureInRow),
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
    required double laneInset,
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    final middleLineY =
        staffTop + staffLineSpacing * ScoreNotationMetrics.middleStaffLineIndex;
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
    final slotCount = _visualSlotCount(measure.symbols);
    const innerPadding = ScoreNotationMetrics.measureInnerPadding;
    final drawableWidth = math.max(
      12.0,
      (measureEndX - measureStartX) - laneInset - innerPadding,
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
            measureStartX + laneInset,
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
      var visualIndex = _visualSlotForIndex(measure.symbols, i);
      if (activeDrag != null) {
        final draggedSlot = _visualSlotForIndex(
          measure.symbols,
          activeDrag.draggedSymbolIndex,
        );
        final compactIndex = visualIndex > draggedSlot
            ? visualIndex - 1
            : visualIndex;
        visualIndex = compactIndex >= activeDrag.targetSymbolIndex
            ? compactIndex + 1
            : compactIndex;
      }
      final progress = (visualIndex + 1) / (slotCount + 1);
      final x = measureStartX + laneInset + (drawableWidth * progress);

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
        if (isPlaying && showPlaybackSymbolHighlight) {
          _drawPlaybackHighlight(canvas, Offset(x, y));
        }
        if (isSelected) _drawSelectionHighlight(canvas, Offset(x, y));
        _drawNote(
          canvas,
          symbol,
          x: x,
          y: y,
          middleLineY: middleLineY,
          suppressFlag: beamedIndices.contains(i),
          drawStem: !beamedIndices.contains(i),
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
        if (isPlaying && showPlaybackSymbolHighlight) {
          _drawPlaybackHighlight(canvas, Offset(x, y));
        }
        if (isSelected) _drawSelectionHighlight(canvas, Offset(x, y));
        _drawRest(canvas, symbol, x: x, staffTop: staffTop);
      }
    }

    // Draw stems and beam bars for groups of 2+.
    _drawBeamBars(
      canvas,
      beamGroups,
      notePositions,
      middleLineY,
      measure.symbols,
    );

    if (!hasDragInMeasure || draggedSymbol == null || !drag.showGhostAtDrag) {
      return;
    }

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

  /// Groups consecutive beamed eighth and sixteenth notes by symbol index.
  /// Chord tones hang on the note before them, so they neither join nor end
  /// a group.
  static List<List<int>> _buildBeamGroups(List<ScoreSymbol> symbols) {
    final groups = <List<int>>[];
    List<int>? current;
    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      if (sym is Note && sym.isChordTone) continue;
      if (sym is Note &&
          (sym.type == 'eighth' || isSixteenthType(sym.type)) &&
          sym.beamed) {
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

  /// A sixteenth note or rest type, as written by scans ('sixteenth') or by
  /// MusicXML ('16th').
  static bool isSixteenthType(String type) {
    final t = type.trim().toLowerCase();
    return t == 'sixteenth' || t == '16th';
  }

  /// Draws the stems and beams of each beam group: one beam across the
  /// group, a second across its sixteenths (a short stub for a lone one).
  /// The beam follows the melody's slope a little and every stem reaches it.
  void _drawBeamBars(
    Canvas canvas,
    List<List<int>> beamGroups,
    Map<int, Offset> notePositions,
    double middleLineY,
    List<ScoreSymbol> symbols,
  ) {
    final beamPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;
    final stemPaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = ScoreNotationMetrics.stemStrokeWidth;

    const stemLen =
        staffLineSpacing * ScoreNotationMetrics.stemLengthStaffSpaces;
    const thickness = ScoreNotationMetrics.beamThickness;
    const levelStep = thickness + ScoreNotationMetrics.beamGap;

    for (final group in beamGroups) {
      if (group.length < 2) continue;
      final heads = [
        for (final i in group)
          if (notePositions[i] != null) notePositions[i]!,
      ];
      if (heads.length != group.length) continue;

      final averageY =
          heads.map((p) => p.dy).reduce((a, b) => a + b) / heads.length;
      final stemUp = averageY > middleLineY;
      final dir = stemUp ? -1.0 : 1.0; // from the heads towards the beam
      final xOff = stemUp
          ? ScoreNotationMetrics.stemXOffset
          : -ScoreNotationMetrics.stemXOffset;
      final xs = [for (final p in heads) p.dx + xOff];
      final run = xs.last - xs.first;
      final slope = run <= 0
          ? 0.0
          : ((heads.last.dy - heads.first.dy) / run).clamp(-0.2, 0.2);

      double line(double x) =>
          heads.first.dy + dir * stemLen + slope * (x - xs.first);
      // Move the beam away from the heads until no stem is shorter than
      // 85 % of a normal one.
      var shift = 0.0;
      for (var k = 0; k < heads.length; k++) {
        final needed = heads[k].dy + dir * stemLen * 0.85 - line(xs[k]);
        shift = stemUp ? math.min(shift, needed) : math.max(shift, needed);
      }
      double beamY(double x) => line(x) + shift;

      for (var k = 0; k < heads.length; k++) {
        canvas.drawLine(
          Offset(xs[k], heads[k].dy),
          Offset(xs[k], beamY(xs[k])),
          stemPaint,
        );
      }

      // Level 0 is the outer beam; inner levels sit nearer the heads.
      void bar(double x1, double x2, int level) {
        final y1 = beamY(x1) - dir * level * levelStep;
        final y2 = beamY(x2) - dir * level * levelStep;
        canvas.drawPath(
          Path()
            ..moveTo(x1, y1)
            ..lineTo(x2, y2)
            ..lineTo(x2, y2 - dir * thickness)
            ..lineTo(x1, y1 - dir * thickness)
            ..close(),
          beamPaint,
        );
      }

      bar(xs.first, xs.last, 0);

      bool sixteenth(int k) {
        final symbol = symbols[group[k]];
        return symbol is Note && isSixteenthType(symbol.type);
      }

      var k = 0;
      while (k < group.length) {
        if (!sixteenth(k)) {
          k++;
          continue;
        }
        var last = k;
        while (last + 1 < group.length && sixteenth(last + 1)) {
          last++;
        }
        if (last > k) {
          bar(xs[k], xs[last], 1);
        } else {
          const stub = 9.0;
          if (k > 0) {
            bar(xs[k] - stub, xs[k], 1);
          } else {
            bar(xs[k], xs[k] + stub, 1);
          }
        }
        k = last + 1;
      }
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
      ..color = ScoreNotationMetrics.playbackSymbolHighlightColor.withValues(
        alpha: 0.18,
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 20, ringPaint);

    // Inner solid fill
    final fillPaint = Paint()
      ..color = ScoreNotationMetrics.playbackSymbolHighlightColor.withValues(
        alpha: 0.45,
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 13, fillPaint);

    // Accent border
    final borderPaint = Paint()
      ..color = ScoreNotationMetrics.playbackSymbolHighlightColor.withValues(
        alpha: 0.8,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 13, borderPaint);
  }

  void _drawPlaybackPlayhead(Canvas canvas, List<_RowMetrics> rows) {
    final partIndex = playheadPartIndex ?? playbackPartIndex;
    final measureIndex = playheadMeasureIndex ?? playbackMeasureIndex;
    final symIndex = playheadSymbolIndex ?? playbackSymbolIndex;
    if (partIndex == null || measureIndex == null) return;

    // Find the row that contains this measure.
    final partRows = rows
        .where((r) => r.partIndex == partIndex)
        .toList()
      ..sort((a, b) => a.globalStartMeasureIndex.compareTo(b.globalStartMeasureIndex));
    if (partRows.isEmpty) return;

    _RowMetrics? currentRow;
    for (final row in partRows) {
      final rel = measureIndex - row.globalStartMeasureIndex;
      if (rel >= 0 && rel < row.measures.length) {
        currentRow = row;
        break;
      }
    }
    if (currentRow == null) return;

    // Locate the measure and compute its slot geometry.
    final measureRelIdx = measureIndex - currentRow.globalStartMeasureIndex;
    if (measureRelIdx < 0 || measureRelIdx >= currentRow.measures.length) return;
    final measure = currentRow.measures[measureRelIdx];

    const ip = ScoreNotationMetrics.measureInnerPadding;
    final measureStartX = currentRow.contentStartX + measureRelIdx * minMeasureWidth;
    final inset = currentRow.laneInset(measureRelIdx);
    final dw = math.max(12.0, minMeasureWidth - inset - ip);
    final laneStartX = measureStartX + inset;

    final symbols = measure.symbols;
    final slotCount = _visualSlotCount(symbols);
    if (slotCount == 0) return;

    // Count how many non-chord-tone symbols appear before symIndex to get the slot.
    final effectiveSymIndex = symIndex ?? 0;
    var slot = 0;
    for (var i = 0; i < effectiveSymIndex && i < symbols.length; i++) {
      final sym = symbols[i];
      if (sym is Note && sym.isChordTone) continue;
      slot++;
    }
    slot = slot.clamp(0, slotCount - 1);

    final currentX = laneStartX + dw * (slot + 1) / (slotCount + 1);

    // Next X: the next symbol in this measure, or the first symbol of the next
    // measure in the same row, or the right barline if at the end of the row.
    double nextX;
    if (slot + 1 < slotCount) {
      nextX = laneStartX + dw * (slot + 2) / (slotCount + 1);
    } else if (measureRelIdx + 1 < currentRow.measures.length) {
      final nextMeasure = currentRow.measures[measureRelIdx + 1];
      final nextMeasureStartX =
          currentRow.contentStartX + (measureRelIdx + 1) * minMeasureWidth;
      final nextInset = currentRow.laneInset(measureRelIdx + 1);
      final nextLaneStartX = nextMeasureStartX + nextInset;
      final nextDw = math.max(12.0, minMeasureWidth - nextInset - ip);
      final nextSlotCount = _visualSlotCount(nextMeasure.symbols);
      nextX = nextSlotCount > 0
          ? nextLaneStartX + nextDw * 1 / (nextSlotCount + 1)
          : nextMeasureStartX + minMeasureWidth;
    } else {
      nextX = currentRow.contentStartX + currentRow.measures.length * minMeasureWidth;
    }

    // Lerp using T (0→1 from AnimationController).
    final t = playbackProgress.clamp(0.0, 1.0);
    final x = currentX + t * (nextX - currentX);

    final verticalPadding = ScoreNotationMetrics.playbackPlayheadStaffPadding;
    final paint = Paint()
      ..color = ScoreNotationMetrics.playbackPlayheadColor.withValues(
        alpha: ScoreNotationMetrics.playbackPlayheadOpacity,
      )
      ..strokeWidth = ScoreNotationMetrics.playbackPlayheadStrokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(x, currentRow.staffTop - verticalPadding),
      Offset(x, currentRow.staffBottom + verticalPadding),
      paint,
    );
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
      NotationPreviewGlyph.wholeRest =>
        staffTop +
            (staffLineSpacing * ScoreNotationMetrics.wholeRestLineIndex) +
            ScoreNotationMetrics.wholeRestCenterYOffset,
      NotationPreviewGlyph.halfRest =>
        staffTop +
            (staffLineSpacing * ScoreNotationMetrics.halfRestLineIndex) +
            ScoreNotationMetrics.halfRestCenterYOffset,
      NotationPreviewGlyph.quarterRest ||
      NotationPreviewGlyph.eighthRest ||
      NotationPreviewGlyph.sixteenthRest =>
        staffTop +
            (staffLineSpacing * ScoreNotationMetrics.quarterRestLineIndex) +
            ScoreNotationMetrics.quarterRestCenterYOffset,
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
      case NotationPreviewGlyph.sixteenthNote:
        _drawNote(
          canvas,
          const Note(step: 'B', octave: 4, duration: 1, type: 'sixteenth'),
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
      case NotationPreviewGlyph.eighthRest:
        _drawRest(
          canvas,
          const Rest(duration: 1, type: 'eighth'),
          x: x,
          staffTop: staffTop,
        );
      case NotationPreviewGlyph.sixteenthRest:
        _drawRest(
          canvas,
          const Rest(duration: 1, type: 'sixteenth'),
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
    bool drawStem = true,
  }) {
    final normalizedType = note.type.trim().toLowerCase();
    final isBreve = normalizedType == 'breve';
    final isWhole = normalizedType == 'whole' || isBreve;
    final isHalf = normalizedType == 'half';
    final isEighth =
        normalizedType == 'eighth' ||
        normalizedType == 'flag8thup' ||
        normalizedType == 'flag8thdown';

    final headWidth = isWhole
        ? ScoreNotationMetrics.noteheadWholeWidth
        : ScoreNotationMetrics.noteheadDefaultWidth;
    final headHeight = isWhole
        ? ScoreNotationMetrics.noteheadWholeHeight
        : ScoreNotationMetrics.noteheadDefaultHeight;

    final fillPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ScoreNotationMetrics.openNoteStrokeWidth;

    // Draw accidental to the left of the notehead.
    if (note.alter != null) {
      final accidentalText = switch (note.alter) {
        1 => ScoreNotationMetrics.sharpGlyph,
        -1 => ScoreNotationMetrics.flatGlyph,
        0 => ScoreNotationMetrics.naturalGlyph,
        2 => ScoreNotationMetrics.doubleSharpGlyph,
        -2 => ScoreNotationMetrics.doubleFlatGlyph,
        _ => null,
      };
      if (accidentalText != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: accidentalText,
            style: const TextStyle(
              fontSize: ScoreNotationMetrics.accidentalFontSize,
              fontFamily: ScoreNotationMetrics.musicFontFamily,
              color: Color(0xFF111827),
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // x is the head's centre: the accidental ends a gap before its left
        // edge.
        tp.paint(
          canvas,
          Offset(
            x - headWidth / 2 - tp.width - ScoreNotationMetrics.accidentalGap,
            y - tp.height * 0.6,
          ),
        );
      }
    }

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(ScoreNotationMetrics.noteheadRotation);
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

    if (isBreve) {
      final sidePaint = Paint()
        ..color = const Color(0xFF111827)
        ..strokeWidth = ScoreNotationMetrics.openNoteStrokeWidth;
      final sideOffset =
          headWidth * ScoreNotationMetrics.breveSideLineOffsetFactor;
      const halfHeight = ScoreNotationMetrics.breveSideLineHalfHeight;
      canvas.drawLine(
        Offset(x - sideOffset, y - halfHeight),
        Offset(x - sideOffset, y + halfHeight),
        sidePaint,
      );
      canvas.drawLine(
        Offset(x + sideOffset, y - halfHeight),
        Offset(x + sideOffset, y + halfHeight),
        sidePaint,
      );
    }

    if (isWhole) {
      _drawAugmentationDots(
        canvas,
        x: x + headWidth * ScoreNotationMetrics.breveSideLineOffsetFactor,
        y: y,
        dots: note.dots,
      );
      return;
    }

    if (note.isChordTone) {
      _drawAugmentationDots(
        canvas,
        x: x + headWidth * ScoreNotationMetrics.breveSideLineOffsetFactor,
        y: y,
        dots: note.dots,
      );
      return;
    }

    if (drawStem) {
      final flags = suppressFlag
          ? 0
          : isEighth
          ? 1
          : isSixteenthType(normalizedType)
          ? 2
          : 0;
      _drawStemAndFlag(
        canvas,
        x: x,
        y: y,
        stemUp: y > middleLineY,
        flags: flags,
      );
    }
    _drawAugmentationDots(
      canvas,
      x: x + headWidth * ScoreNotationMetrics.breveSideLineOffsetFactor,
      y: y,
      dots: note.dots,
    );
  }

  void _drawStemAndFlag(
    Canvas canvas, {
    required double x,
    required double y,
    required bool stemUp,
    required int flags,
  }) {
    final stemPaint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = ScoreNotationMetrics.stemStrokeWidth;

    final stemLength = ScoreNotationMetrics.stemLengthFor(staffLineSpacing);
    final stemX = stemUp
        ? x + ScoreNotationMetrics.stemXOffset
        : x - ScoreNotationMetrics.stemXOffset;
    final endY = stemUp ? y - stemLength : y + stemLength;

    canvas.drawLine(Offset(stemX, y), Offset(stemX, endY), stemPaint);

    // Filled and outlined, so one flag reads as one solid hook (an outline
    // alone looks like two strokes, i.e. like a sixteenth's two flags).
    final flagPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill
      ..strokeWidth = ScoreNotationMetrics.flagStrokeWidth;
    final flagOutline = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ScoreNotationMetrics.flagStrokeWidth;
    // Each further flag sits a little nearer the notehead.
    for (var f = 0; f < flags; f++) {
      final fy = stemUp
          ? endY + f * ScoreNotationMetrics.flagSpacing
          : endY - f * ScoreNotationMetrics.flagSpacing;
      final path = Path();
      if (stemUp) {
        path.moveTo(stemX, fy + 0.5);
        path.quadraticBezierTo(stemX + 10, fy + 2, stemX + 6, fy + 12);
        path.quadraticBezierTo(stemX + 8, fy + 8, stemX + 1, fy + 6);
      } else {
        // Flags point right on a down stem too, curving up towards the head.
        path.moveTo(stemX, fy - 0.5);
        path.quadraticBezierTo(stemX + 10, fy - 2, stemX + 6, fy - 12);
        path.quadraticBezierTo(stemX + 8, fy - 8, stemX + 1, fy - 6);
      }
      path.close();
      canvas
        ..drawPath(path, flagPaint)
        ..drawPath(path, flagOutline);
    }
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
      final line4Y =
          staffTop +
          (staffLineSpacing * ScoreNotationMetrics.wholeRestLineIndex);
      final rect = Rect.fromCenter(
        center: Offset(x, line4Y + ScoreNotationMetrics.wholeRestCenterYOffset),
        width: ScoreNotationMetrics.restRectWidth,
        height: ScoreNotationMetrics.restRectHeight,
      );
      canvas.drawRect(rect, paint);
      _drawAugmentationDots(
        canvas,
        x: x + ScoreNotationMetrics.restDotXOffset,
        y: line4Y + ScoreNotationMetrics.wholeRestCenterYOffset,
        dots: rest.dots,
      );
      return;
    }

    if (type == 'half') {
      final line3Y =
          staffTop +
          (staffLineSpacing * ScoreNotationMetrics.halfRestLineIndex);
      final rect = Rect.fromCenter(
        center: Offset(x, line3Y + ScoreNotationMetrics.halfRestCenterYOffset),
        width: ScoreNotationMetrics.restRectWidth,
        height: ScoreNotationMetrics.restRectHeight,
      );
      canvas.drawRect(rect, paint);
      _drawAugmentationDots(
        canvas,
        x: x + ScoreNotationMetrics.restDotXOffset,
        y: line3Y + ScoreNotationMetrics.halfRestCenterYOffset,
        dots: rest.dots,
      );
      return;
    }

    if (type == 'eighth' || isSixteenthType(type)) {
      final glyph = TextPainter(
        text: TextSpan(
          text: type == 'eighth'
              ? ScoreNotationMetrics.eighthRestGlyph
              : ScoreNotationMetrics.sixteenthRestGlyph,
          style: const TextStyle(
            fontSize: ScoreNotationMetrics.restGlyphFontSize,
            fontFamily: ScoreNotationMetrics.musicFontFamily,
            color: Color(0xFF111827),
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final middleY = staffTop + staffLineSpacing * 2;
      glyph.paint(
        canvas,
        Offset(
          x - glyph.width / 2,
          middleY -
              glyph.height / 2 +
              (type == 'eighth'
                  ? 0
                  : ScoreNotationMetrics.sixteenthRestYOffset),
        ),
      );
      _drawAugmentationDots(
        canvas,
        x: x + ScoreNotationMetrics.quarterRestDotXOffset,
        y: middleY - staffLineSpacing / 2,
        dots: rest.dots,
      );
      return;
    }

    final y =
        staffTop +
        (staffLineSpacing * ScoreNotationMetrics.quarterRestLineIndex);
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
    _drawAugmentationDots(
      canvas,
      x: x + ScoreNotationMetrics.quarterRestDotXOffset,
      y: y + ScoreNotationMetrics.quarterRestDotYOffset,
      dots: rest.dots,
    );
  }

  void _drawAugmentationDots(
    Canvas canvas, {
    required double x,
    required double y,
    required int dots,
  }) {
    if (dots <= 0) return;

    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < dots; i++) {
      canvas.drawCircle(
        Offset(
          x + (i * ScoreNotationMetrics.dotSpacing),
          y + ScoreNotationMetrics.dotYOffset,
        ),
        ScoreNotationMetrics.dotRadius,
        paint,
      );
    }
  }

  static int _visualSlotCount(List<ScoreSymbol> symbols) {
    var count = 0;
    for (final symbol in symbols) {
      if (symbol is Note && symbol.isChordTone) {
        continue;
      }
      count++;
    }
    return math.max(count, 1);
  }

  static int _visualSlotForIndex(List<ScoreSymbol> symbols, int index) {
    var slot = -1;
    for (var i = 0; i <= index; i++) {
      final symbol = symbols[i];
      if (symbol is Note && symbol.isChordTone) {
        continue;
      }
      slot++;
    }
    return math.max(slot, 0);
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
    final bottom = y + ScoreNotationMetrics.staffHeightFor(staffLineSpacing);
    // clefLine: 1 = bottom, 5 = top  →  Y decreases going up
    final targetY = y + (4 - (clefLine - 1)) * staffLineSpacing;

    // Left vertical bar (spine)
    canvas.drawRect(
      Rect.fromLTWH(x, top, ScoreNotationMetrics.cClefSpineWidth, bottom - top),
      fill,
    );

    // Upper bracket
    stroke.strokeWidth = ScoreNotationMetrics.cClefBracketStrokeWidth;
    canvas.drawLine(
      Offset(x + ScoreNotationMetrics.cClefSpineWidth, top),
      Offset(x + 14, top),
      stroke,
    );
    stroke.strokeWidth = ScoreNotationMetrics.cClefVerticalStrokeWidth;
    canvas.drawLine(Offset(x + 14, top), Offset(x + 14, targetY), stroke);

    // Lower bracket
    stroke.strokeWidth = ScoreNotationMetrics.cClefBracketStrokeWidth;
    canvas.drawLine(
      Offset(x + ScoreNotationMetrics.cClefSpineWidth, bottom),
      Offset(x + 14, bottom),
      stroke,
    );
    stroke.strokeWidth = ScoreNotationMetrics.cClefVerticalStrokeWidth;
    canvas.drawLine(Offset(x + 14, targetY), Offset(x + 14, bottom), stroke);

    // Centre line at the target staff line
    stroke.strokeWidth = ScoreNotationMetrics.cClefCenterStrokeWidth;
    canvas.drawLine(
      Offset(x + ScoreNotationMetrics.cClefSpineWidth, targetY),
      Offset(x + 12, targetY),
      stroke,
    );
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
      ..strokeWidth = ScoreNotationMetrics.systemConnectorStrokeWidth
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
        text: ScoreNotationMetrics.trebleClefGlyph,
        style: TextStyle(
          fontSize: ScoreNotationMetrics.trebleClefFontSize,
          fontFamily: ScoreNotationMetrics.musicFontFamily,
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
      ..strokeWidth = ScoreNotationMetrics.bassClefStrokeWidth
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
      ScoreNotationMetrics.bassClefDotRadius,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(dotX, cy + staffLineSpacing * 0.4),
      ScoreNotationMetrics.bassClefDotRadius,
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
    final accidental = isSharp
        ? ScoreNotationMetrics.sharpGlyph
        : ScoreNotationMetrics.flatGlyph;

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
    const sharpOrderAlto = [
      ('F', 4),
      ('C', 4),
      ('G', 4),
      ('D', 4),
      ('A', 4),
      ('E', 4),
      ('B', 4),
    ];
    const flatOrderAlto = [
      ('B', 3),
      ('E', 4),
      ('A', 3),
      ('D', 4),
      ('G', 3),
      ('C', 4),
      ('F', 3),
    ];
    const sharpOrderTenor = [
      ('F', 3),
      ('C', 4),
      ('G', 3),
      ('D', 4),
      ('A', 3),
      ('E', 4),
      ('B', 3),
    ];
    const flatOrderTenor = [
      ('B', 3),
      ('E', 4),
      ('A', 3),
      ('D', 4),
      ('G', 3),
      ('C', 4),
      ('F', 3),
    ];

    final isBass = clefSign.toUpperCase() == 'F';
    final isAlto = clefSign.toUpperCase() == 'C' && clefLine == 3;
    final isTenor = clefSign.toUpperCase() == 'C' && clefLine == 4;
    final order = isSharp
        ? (isBass
              ? sharpOrderBass
              : isAlto
              ? sharpOrderAlto
              : isTenor
              ? sharpOrderTenor
              : sharpOrderTreble)
        : (isBass
              ? flatOrderBass
              : isAlto
              ? flatOrderAlto
              : isTenor
              ? flatOrderTenor
              : flatOrderTreble);

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
            fontSize: ScoreNotationMetrics.keySignatureFontSize,
            fontFamily: ScoreNotationMetrics.musicFontFamily,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w500,
            // The music font's own line box is tall and would hang the
            // glyph two steps low; placed like a note's accidental instead.
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x, y - textPainter.height * 0.6));
      x += ScoreNotationMetrics.keySignatureSpacing;
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
          fontSize: ScoreNotationMetrics.timeSignatureFontSize,
          fontFamily: ScoreNotationMetrics.textFontFamily,
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
          fontSize: ScoreNotationMetrics.timeSignatureFontSize,
          fontFamily: ScoreNotationMetrics.textFontFamily,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    top.paint(canvas, Offset(x, y));
    bottom.paint(
      canvas,
      Offset(
        x,
        y +
            staffLineSpacing *
                ScoreNotationMetrics.timeSignatureBottomOffsetSpaces,
      ),
    );
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
        oldDelegate.playbackNextPartIndex != playbackNextPartIndex ||
        oldDelegate.playbackNextMeasureIndex != playbackNextMeasureIndex ||
        oldDelegate.playbackNextSymbolIndex != playbackNextSymbolIndex ||
        oldDelegate.playheadPartIndex != playheadPartIndex ||
        oldDelegate.playheadMeasureIndex != playheadMeasureIndex ||
        oldDelegate.playheadSymbolIndex != playheadSymbolIndex ||
        oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.showPlaybackSymbolHighlight !=
            showPlaybackSymbolHighlight ||
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
  sixteenthNote,
  wholeRest,
  halfRest,
  quarterRest,
  eighthRest,
  sixteenthRest,
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
    this.showGhostAtDrag = true,
  });

  final int measureIndex;
  final int draggedSymbolIndex;
  final int targetSymbolIndex;
  final double dragX;
  final bool showGhostAtDrag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotationDragFeedback &&
          runtimeType == other.runtimeType &&
          measureIndex == other.measureIndex &&
          draggedSymbolIndex == other.draggedSymbolIndex &&
          targetSymbolIndex == other.targetSymbolIndex &&
          dragX == other.dragX &&
          showGhostAtDrag == other.showGhostAtDrag;

  @override
  int get hashCode =>
      measureIndex.hashCode ^
      draggedSymbolIndex.hashCode ^
      targetSymbolIndex.hashCode ^
      dragX.hashCode ^
      showGhostAtDrag.hashCode;
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
    required this.timeInPrefix,
    required this.timeInMeasure,
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

  /// The row's time signature goes before its opening barline.
  final bool timeInPrefix;

  /// Per measure: its time signature goes inside it, after its barline.
  final List<bool> timeInMeasure;

  /// Gap before the first symbol of the measure at [measureInRow].
  double laneInset(int measureInRow) => ScoreNotationMetrics.laneInset(
    timeInMeasure: timeInMeasure[measureInRow],
  );

  String get clefSign => clef?.sign ?? 'G';
  int get clefLine => clef?.line ?? 2;
}
