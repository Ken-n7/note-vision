import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/core/widgets/score_notation/staff_pitch_mapper.dart';
import 'package:pdf/pdf.dart';

/// Renders a [Score] as an engraved A4 PDF and returns the raw bytes.
///
/// Uses the same pitch-to-position math as [ScoreNotationPainter] so that
/// the PDF output matches the editor canvas layout.
class PdfScoreRenderer {
  const PdfScoreRenderer({this.compress = true});

  /// PDF stream compression. Tests can disable this to inspect generated
  /// content streams without changing production output.
  final bool compress;

  // ── Page & layout constants ──────────────────────────────────────────────
  // These mirror EditorLayoutPolicy.standard so exported pages use the same
  // measure grouping as the editor canvas.
  static const double _editorPageW = 760.0;
  static const double _editorPageH = 1120.0;
  static const double _editorPadX = 16.0;
  static const double _editorPadY = 28.0;
  static const double _editorRowH = 140.0;
  static const double _editorPrefixW = 86.0;
  static const double _editorLineSpacing =
      ScoreNotationMetrics.staffLineSpacing;
  static const double _editorStaffTopOffset = 28.0;
  static const int _measuresPerSystem = 4;
  static const int _baseRowsPerPage = 5;

  static final double _scale = PdfPageFormat.a4.height / _editorPageH;
  static final double _pageX0 =
      (PdfPageFormat.a4.width - _editorPageW * _scale) / 2;
  static final double _pageY0 =
      (PdfPageFormat.a4.height - _editorPageH * _scale) / 2;
  static final double _padX = _editorPadX * _scale;
  static final double _padY = _editorPadY * _scale;
  static final double _prefixW = _editorPrefixW * _scale;
  static final double _mw =
      ((_editorPageW - _editorPadX * 2 - _editorPrefixW) / _measuresPerSystem) *
      _scale;
  static final double _ls = _editorLineSpacing * _scale;
  static final double _staffH = ScoreNotationMetrics.staffHeightFor(_ls);

  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns raw PDF bytes for [score].
  Future<Uint8List> render(Score score) async {
    final doc = PdfDocument(compress: compress);
    final font = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.textFontAsset),
    );
    final fontBold = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.textBoldFontAsset),
    );
    final musicFont = PdfTtfFont(
      doc,
      await rootBundle.load(ScoreNotationMetrics.musicFontAsset),
    );

    if (score.parts.isEmpty) {
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _text(
        g,
        fontBold,
        14,
        'Empty score',
        _pageX0 + _padX,
        PdfPageFormat.a4.height - _pageY0 - _padY - 14,
      );
      return doc.save();
    }

    final pages = _paginate(score);

    for (final pageData in pages) {
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _paintPage(
        g,
        pageData,
        score,
        font,
        fontBold,
        musicFont,
        PdfPageFormat.a4,
      );
    }

    return doc.save();
  }

  List<PdfPageLayoutInfo> debugPageLayoutForTesting(Score score) {
    return _paginate(score)
        .map(
          (page) => PdfPageLayoutInfo(
            firstMeasureIndex: page.firstMeasureIndex,
            measureCount: page.measureCount,
            measuresPerSystem: page.measuresPerSystem,
            rowsPerPage: page.rowsPerPage,
          ),
        )
        .toList(growable: false);
  }

  List<List<Measure>> debugPageSliceForTesting(Score score, int pageIndex) {
    final pages = _paginate(score);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const <List<Measure>>[];
    }
    return _sliceScoreForPage(score, pages[pageIndex]);
  }

  double debugPitchYForTesting({
    required String step,
    required int octave,
    required double staffBottom,
    String clefSign = 'G',
    int clefLine = 2,
  }) {
    return _yForPitch(
      step: step,
      octave: octave,
      bottomLineY: staffBottom,
      clefSign: clefSign,
      clefLine: clefLine,
    );
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  List<_PageData> _paginate(Score score) {
    final partCount = score.parts.length;
    final rowsPerPage = _rowsPerPageForPartCount(partCount);
    final referenceMeasures = score.parts.isEmpty
        ? const <Measure>[]
        : score.parts.first.measures;
    final pageStarts = _pageStartIndices(
      referenceMeasures,
      rowsPerPage: rowsPerPage,
    );
    final result = <_PageData>[];

    for (var i = 0; i < pageStarts.length; i++) {
      final firstMeasureIndex = pageStarts[i];
      final nextMeasureIndex = i + 1 < pageStarts.length
          ? pageStarts[i + 1]
          : referenceMeasures.length;
      result.add(
        _PageData(
          firstMeasureIndex: firstMeasureIndex,
          measureCount: math.max(0, nextMeasureIndex - firstMeasureIndex),
          measuresPerSystem: _measuresPerSystem,
          rowsPerPage: rowsPerPage,
        ),
      );
    }

    if (result.isEmpty) {
      result.add(
        _PageData(
          firstMeasureIndex: 0,
          measureCount: 0,
          measuresPerSystem: _measuresPerSystem,
          rowsPerPage: rowsPerPage,
        ),
      );
    }
    return result;
  }

  static int _rowsPerPageForPartCount(int partCount) {
    final normalizedPartCount = math.max(1, partCount);
    final availableHeight = _editorPageH - (_editorPadY * 2);
    final maxRowsThatFit =
        (availableHeight / (normalizedPartCount * _editorRowH)).floor();
    return math.max(1, math.min(_baseRowsPerPage, maxRowsThatFit));
  }

  static List<int> _pageStartIndices(
    List<Measure> measures, {
    required int rowsPerPage,
  }) {
    if (measures.isEmpty) return const [0];

    final hasExplicitBreaks = measures.any((m) => m.startsNewPage);
    if (!hasExplicitBreaks) {
      final measuresPerPage = _measuresPerSystem * rowsPerPage;
      final count = math.max(
        1,
        (measures.length + measuresPerPage - 1) ~/ measuresPerPage,
      );
      return List.generate(count, (i) => i * measuresPerPage);
    }

    final indices = <int>[0];
    for (var i = 1; i < measures.length; i++) {
      if (measures[i].startsNewPage) indices.add(i);
    }
    return indices;
  }

  List<List<Measure>> _sliceScoreForPage(Score score, _PageData page) {
    return score.parts
        .map(
          (part) => _sliceMeasuresWithInheritedMetadata(
            measures: part.measures,
            firstMeasureIndex: page.firstMeasureIndex,
            pageMeasureCount: page.measureCount,
          ),
        )
        .toList(growable: false);
  }

  List<Measure> _sliceMeasuresWithInheritedMetadata({
    required List<Measure> measures,
    required int firstMeasureIndex,
    required int pageMeasureCount,
  }) {
    final start = firstMeasureIndex.clamp(0, measures.length);
    final end = (start + pageMeasureCount).clamp(start, measures.length);

    Clef? activeClef;
    TimeSignature? activeTimeSignature;
    KeySignature? activeKeySignature;

    for (var i = 0; i < start; i++) {
      final measure = measures[i];
      activeClef = measure.clef ?? activeClef;
      activeTimeSignature = measure.timeSignature ?? activeTimeSignature;
      activeKeySignature = measure.keySignature ?? activeKeySignature;
    }

    final slice = <Measure>[];
    for (var i = start; i < end; i++) {
      final measure = measures[i];
      final normalized = Measure(
        number: measure.number,
        clef: measure.clef ?? activeClef,
        timeSignature: measure.timeSignature ?? activeTimeSignature,
        keySignature: measure.keySignature ?? activeKeySignature,
        symbols: measure.symbols,
        startsNewPage: measure.startsNewPage,
        startsNewSystem: measure.startsNewSystem,
        leftBarlineType: measure.leftBarlineType,
        rightBarlineType: measure.rightBarlineType,
      );
      slice.add(normalized);
      activeClef = normalized.clef;
      activeTimeSignature = normalized.timeSignature;
      activeKeySignature = normalized.keySignature;
    }

    return slice;
  }

  // ── Page painter ──────────────────────────────────────────────────────────

  void _paintPage(
    PdfGraphics g,
    _PageData page,
    Score score,
    PdfFont font,
    PdfFont fontBold,
    PdfFont musicFont,
    PdfPageFormat fmt,
  ) {
    final pageH = fmt.height;
    final partCount = score.parts.length;
    final pageParts = _sliceScoreForPage(score, page);
    final maxMeasures = pageParts.fold(0, (m, p) => math.max(m, p.length));
    final systemCount = maxMeasures == 0
        ? 0
        : (maxMeasures / page.measuresPerSystem).ceil();

    for (var s = 0; s < systemCount; s++) {
      final startM = s * page.measuresPerSystem;

      for (var pi = 0; pi < partCount; pi++) {
        final partMeasures = pageParts[pi];
        if (startM >= partMeasures.length) continue;

        final endM = math.min(
          startM + page.measuresPerSystem,
          partMeasures.length,
        );
        final rowMeasures = partMeasures.sublist(startM, endM);

        // staffTop = top staff line in PDF coords (y from bottom).
        final editorStaffTop =
            _editorPadY +
            s * partCount * _editorRowH +
            pi * _editorRowH +
            _editorStaffTopOffset;
        final staffTop = pageH - _pageY0 - editorStaffTop * _scale;

        _drawStaffRow(
          g,
          font,
          fontBold,
          musicFont,
          rowMeasures: rowMeasures,
          staffTop: staffTop,
          clefSign: _clefSign(rowMeasures),
          clefLine: _clefLine(rowMeasures),
          isFirstSystem: s == 0,
        );
      }
    }
  }

  // ── Staff row ──────────────────────────────────────────────────────────────

  void _drawStaffRow(
    PdfGraphics g,
    PdfFont font,
    PdfFont fontBold,
    PdfFont musicFont, {
    required List<Measure> rowMeasures,
    required double staffTop,
    required String clefSign,
    required int clefLine,
    required bool isFirstSystem,
  }) {
    // staffTop = y of top staff line (PDF: y from bottom)
    // staffBottom = y of bottom staff line
    final staffBottom = staffTop - _staffH;
    final rowStartX = _pageX0 + _padX;
    final contentStartX = rowStartX + _prefixW;
    final staffEndX = contentStartX + rowMeasures.length * _mw;

    // 5 staff lines
    for (var i = 0; i < ScoreNotationMetrics.staffLineCount; i++) {
      final lineY = staffTop - i * _ls;
      _line(
        g,
        rowStartX,
        lineY,
        staffEndX,
        lineY,
        ScoreNotationMetrics.staffLineStrokeWidth * _scale,
      );
    }

    // Opening barline
    _line(
      g,
      contentStartX,
      staffTop,
      contentStartX,
      staffBottom,
      ScoreNotationMetrics.barlineStrokeWidth * _scale,
    );
    // Closing barline
    _line(
      g,
      staffEndX,
      staffTop,
      staffEndX,
      staffBottom,
      ScoreNotationMetrics.barlineStrokeWidth * _scale,
    );

    // Clef
    if (clefSign.toUpperCase() == 'F') {
      _drawBassClef(g, rowStartX + 8 * _scale, staffTop, staffBottom);
    } else if (clefSign.toUpperCase() == 'C') {
      _drawCClef(
        g,
        rowStartX + 6 * _scale,
        staffTop,
        staffBottom,
        clefLine: clefLine,
      );
    } else {
      _drawTrebleClef(g, musicFont, rowStartX + 10 * _scale, staffTop);
    }

    // Key + time signature (first visible system on each editor/PDF page)
    var sigX = rowStartX + ScoreNotationMetrics.rowSignatureStartX * _scale;
    if (isFirstSystem && rowMeasures.isNotEmpty) {
      final first = rowMeasures.first;
      if (first.keySignature != null) {
        sigX = _drawKeySignature(
          g,
          musicFont,
          sigX,
          first.keySignature!.fifths,
          staffBottom: staffBottom,
          clefSign: clefSign,
          clefLine: clefLine,
        );
      }
      if (first.timeSignature != null) {
        _drawTimeSig(
          g,
          fontBold,
          sigX + 10 * _scale,
          staffTop,
          first.timeSignature!.beats,
          first.timeSignature!.beatType,
        );
      }
    }

    // Measures
    for (var mi = 0; mi < rowMeasures.length; mi++) {
      final measure = rowMeasures[mi];
      final measureStartX = contentStartX + mi * _mw;
      final measureEndX = measureStartX + _mw;

      // Measure barline (except before first)
      if (mi > 0) {
        _line(
          g,
          measureStartX,
          staffTop,
          measureStartX,
          staffBottom,
          ScoreNotationMetrics.barlineStrokeWidth * _scale,
        );
      }

      // Measure number
      _text(
        g,
        font,
        ScoreNotationMetrics.measureNumberFontSize * _scale,
        '${measure.number}',
        measureStartX + ScoreNotationMetrics.measureNumberOffsetX * _scale,
        staffTop - ScoreNotationMetrics.measureNumberOffsetY * _scale,
      );

      _drawMeasureSymbols(
        g,
        musicFont,
        measure,
        measureStartX: measureStartX,
        measureEndX: measureEndX,
        staffTop: staffTop,
        staffBottom: staffBottom,
        clefSign: clefSign,
        clefLine: clefLine,
      );
    }
  }

  // ── Measure symbols ────────────────────────────────────────────────────────

  void _drawMeasureSymbols(
    PdfGraphics g,
    PdfFont musicFont,
    Measure measure, {
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    if (measure.symbols.isEmpty) return;

    final innerPad = ScoreNotationMetrics.measureInnerPadding * _scale;
    final drawableW = math.max(
      12.0,
      (measureEndX - measureStartX) - innerPad * 2,
    );
    final count = measure.symbols.length;
    final slotCount = _visualSlotCount(measure.symbols);
    final middleLineY =
        staffTop - _ls * ScoreNotationMetrics.middleStaffLineIndex;

    // Pre-compute x/y positions for all symbols.
    final xs = List<double>.generate(
      count,
      (i) =>
          measureStartX +
          innerPad +
          drawableW *
              (_visualSlotForIndex(measure.symbols, i) + 1) /
              (slotCount + 1),
    );
    final ys = <double>[];
    for (var i = 0; i < count; i++) {
      final sym = measure.symbols[i];
      if (sym is Note) {
        ys.add(
          _yForPitch(
            step: sym.step,
            octave: sym.octave,
            bottomLineY: staffBottom,
            clefSign: clefSign,
            clefLine: clefLine,
          ),
        );
      } else {
        ys.add(staffTop - _ls * ScoreNotationMetrics.middleStaffLineIndex);
      }
    }

    // Build beam groups: runs of consecutive beamed eighth notes.
    final beamGroups = _buildBeamGroups(measure.symbols);
    final beamedIndices = <int>{};
    for (final group in beamGroups) {
      if (group.length >= 2) {
        beamedIndices.addAll(group);
      }
    }

    // Draw notes/rests.
    for (var i = 0; i < count; i++) {
      final symbol = measure.symbols[i];
      final x = xs[i];
      final y = ys[i];

      if (symbol is Note) {
        _drawNote(
          g,
          musicFont,
          symbol,
          x: x,
          y: y,
          middleLineY: middleLineY,
          suppressFlag: beamedIndices.contains(i),
        ); // suppressFlag hides individual flag when note is part of a beam group
      } else if (symbol is Rest) {
        _drawRest(g, symbol, x: x, staffTop: staffTop);
      }
    }

    // Draw beam bars for groups of 2+.
    for (final group in beamGroups) {
      if (group.length < 2) continue;
      final first = group.first;
      final last = group.last;
      final firstY = ys[first];
      final lastY = ys[last];
      final stemUp = firstY < middleLineY;
      final stemLen = ScoreNotationMetrics.stemLengthFor(_ls);
      final stemOffX =
          (stemUp
              ? ScoreNotationMetrics.stemXOffset
              : -ScoreNotationMetrics.stemXOffset) *
          _scale;

      // Beam connects the stem tips of all notes in the group.
      final x1 = xs[first] + stemOffX;
      final x2 = xs[last] + stemOffX;
      final y1 = stemUp ? firstY + stemLen : firstY - stemLen;
      final y2 = stemUp ? lastY + stemLen : lastY - stemLen;

      final beamThickness = ScoreNotationMetrics.beamThickness * _scale;
      g.setColor(_ink);
      g.drawRect(
        x1,
        math.min(y1, y2) - beamThickness / 2,
        x2 - x1,
        beamThickness,
      );
      g.fillPath();
    }
  }

  /// Groups indices of consecutive beamed eighth notes.
  List<List<int>> _buildBeamGroups(List<dynamic> symbols) {
    final groups = <List<int>>[];
    List<int>? current;

    for (var i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      if (sym is Note &&
          !sym.isChordTone &&
          _isEighth(sym.type) &&
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

  double _yForPitch({
    required String step,
    required int octave,
    required double bottomLineY,
    required String clefSign,
    required int clefLine,
  }) {
    return StaffPitchMapper.yForPitch(
      step: step,
      octave: octave,
      bottomLineY: bottomLineY,
      lineSpacing: -_ls,
      clefSign: clefSign,
      clefLine: clefLine,
    );
  }

  // ── Note ──────────────────────────────────────────────────────────────────

  void _drawNote(
    PdfGraphics g,
    PdfFont font,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
    bool suppressFlag = false,
  }) {
    final type = note.type.trim().toLowerCase();
    final isBreve = type == 'breve';
    final isWhole = type == 'whole' || isBreve;
    final isHalf = type == 'half';
    final isEighth = _isEighth(type);

    g.setColor(_ink);

    final accidental = _accidentalLabel(note.alter);
    if (accidental != null) {
      _text(
        g,
        font,
        ScoreNotationMetrics.accidentalFontSize * _scale,
        accidental,
        x - ScoreNotationMetrics.pdfAccidentalXOffset * _scale,
        y - ScoreNotationMetrics.pdfAccidentalYOffset * _scale,
      );
    }

    final headW =
        (isWhole
            ? ScoreNotationMetrics.noteheadWholeWidth
            : ScoreNotationMetrics.noteheadDefaultWidth) *
        _scale;
    final headH =
        (isWhole
            ? ScoreNotationMetrics.noteheadWholeHeight
            : ScoreNotationMetrics.noteheadDefaultHeight) *
        _scale;
    final hw = headW / 2;
    if (isWhole || isHalf) {
      _drawRotatedOval(g, x: x, y: y, width: headW, height: headH, fill: false);
    } else {
      _drawRotatedOval(g, x: x, y: y, width: headW, height: headH, fill: true);
    }

    if (isBreve) {
      _line(
        g,
        x - hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y - ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        x - hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y + ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        ScoreNotationMetrics.openNoteStrokeWidth * _scale,
      );
      _line(
        g,
        x + hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y - ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        x + hw * ScoreNotationMetrics.breveSideLineOffsetFactor * 2,
        y + ScoreNotationMetrics.breveSideLineHalfHeight * _scale,
        ScoreNotationMetrics.openNoteStrokeWidth * _scale,
      );
    }

    if (note.dots > 0) {
      _drawAugmentationDots(
        g,
        x: x + headW * ScoreNotationMetrics.breveSideLineOffsetFactor,
        y: y,
        dots: note.dots,
      );
    }

    if (isWhole) return;

    if (note.isChordTone) {
      return;
    }

    // Stem
    final stemUp = y < middleLineY;
    _drawStem(
      g,
      x: x,
      y: y,
      stemUp: stemUp,
      isEighth: isEighth && !suppressFlag,
    );
  }

  static bool _isEighth(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'eighth' ||
        normalized == 'flag8thup' ||
        normalized == 'flag8thdown';
  }

  String? accidentalLabelForTesting(int? alter) => _accidentalLabel(alter);

  static String? _accidentalLabel(int? alter) => switch (alter) {
    1 => ScoreNotationMetrics.sharpGlyph,
    -1 => ScoreNotationMetrics.flatGlyph,
    0 => ScoreNotationMetrics.naturalGlyph,
    2 => ScoreNotationMetrics.doubleSharpGlyph,
    -2 => ScoreNotationMetrics.doubleFlatGlyph,
    _ => null,
  };

  void _drawStem(
    PdfGraphics g, {
    required double x,
    required double y,
    required bool stemUp,
    required bool isEighth,
  }) {
    final stemLen = ScoreNotationMetrics.stemLengthFor(_ls);
    final stemX = stemUp
        ? x + ScoreNotationMetrics.stemXOffset * _scale
        : x - ScoreNotationMetrics.stemXOffset * _scale;
    final endY = stemUp ? y + stemLen : y - stemLen;

    g.setColor(_ink);
    _line(
      g,
      stemX,
      y,
      stemX,
      endY,
      ScoreNotationMetrics.stemStrokeWidth * _scale,
    );

    if (!isEighth) return;

    g.setLineWidth(ScoreNotationMetrics.flagStrokeWidth * _scale);
    g.setColor(_ink);
    if (stemUp) {
      final start = _pdfOffset(stemX, endY, 0, 0.5);
      g.moveTo(start.x, start.y);
      _quadraticCurveTo(
        g,
        fromX: start.x,
        fromY: start.y,
        controlX: stemX + 10 * _scale,
        controlY: endY - 2 * _scale,
        endX: stemX + 6 * _scale,
        endY: endY - 12 * _scale,
      );
      _quadraticCurveTo(
        g,
        fromX: stemX + 6 * _scale,
        fromY: endY - 12 * _scale,
        controlX: stemX + 8 * _scale,
        controlY: endY - 8 * _scale,
        endX: stemX + 1 * _scale,
        endY: endY - 6 * _scale,
      );
    } else {
      final start = _pdfOffset(stemX, endY, 0, -0.5);
      g.moveTo(start.x, start.y);
      _quadraticCurveTo(
        g,
        fromX: start.x,
        fromY: start.y,
        controlX: stemX - 10 * _scale,
        controlY: endY + 2 * _scale,
        endX: stemX - 6 * _scale,
        endY: endY + 12 * _scale,
      );
      _quadraticCurveTo(
        g,
        fromX: stemX - 6 * _scale,
        fromY: endY + 12 * _scale,
        controlX: stemX - 8 * _scale,
        controlY: endY + 8 * _scale,
        endX: stemX - 1 * _scale,
        endY: endY + 6 * _scale,
      );
    }
    g.strokePath();
  }

  // ── Rest ──────────────────────────────────────────────────────────────────

  void _drawRest(
    PdfGraphics g,
    Rest rest, {
    required double x,
    required double staffTop,
  }) {
    final type = rest.type.trim().toLowerCase();
    g.setColor(_ink);

    if (type == 'whole') {
      // Rectangle hanging below line 4 (from top)
      final lineY = staffTop - _ls * ScoreNotationMetrics.wholeRestLineIndex;
      final height = ScoreNotationMetrics.restRectHeight * _scale;
      final centerY =
          lineY - ScoreNotationMetrics.wholeRestCenterYOffset * _scale;
      g.drawRect(
        x - ScoreNotationMetrics.restRectWidth * _scale / 2,
        centerY - height / 2,
        ScoreNotationMetrics.restRectWidth * _scale,
        height,
      );
      g.fillPath();
      _drawAugmentationDots(
        g,
        x: x + ScoreNotationMetrics.restDotXOffset * _scale,
        y: centerY,
        dots: rest.dots,
      );
      return;
    }

    if (type == 'half') {
      // Rectangle sitting on line 3 (from top)
      final lineY = staffTop - _ls * ScoreNotationMetrics.halfRestLineIndex;
      final height = ScoreNotationMetrics.restRectHeight * _scale;
      final centerY =
          lineY - ScoreNotationMetrics.halfRestCenterYOffset * _scale;
      g.drawRect(
        x - ScoreNotationMetrics.restRectWidth * _scale / 2,
        centerY - height / 2,
        ScoreNotationMetrics.restRectWidth * _scale,
        height,
      );
      g.fillPath();
      _drawAugmentationDots(
        g,
        x: x + ScoreNotationMetrics.restDotXOffset * _scale,
        y: centerY,
        dots: rest.dots,
      );
      return;
    }

    final qy = staffTop - _ls * ScoreNotationMetrics.quarterRestLineIndex;
    _moveToOffset(g, x, qy, -3, -5);
    _lineToOffset(g, x, qy, 3, -1);
    _lineToOffset(g, x, qy, -2, 4);
    _lineToOffset(g, x, qy, 3, 9);
    _lineToOffset(g, x, qy, -1, 14);
    _lineToOffset(g, x, qy, 3, 19);
    _lineToOffset(g, x, qy, -4, 22);
    _lineToOffset(g, x, qy, -1, 16);
    _lineToOffset(g, x, qy, -6, 11);
    _lineToOffset(g, x, qy, -1, 5);
    g.closePath();
    g.fillPath();
    _drawAugmentationDots(
      g,
      x: x + ScoreNotationMetrics.quarterRestDotXOffset * _scale,
      y: qy - ScoreNotationMetrics.quarterRestDotYOffset * _scale,
      dots: rest.dots,
    );
  }

  void _drawAugmentationDots(
    PdfGraphics g, {
    required double x,
    required double y,
    required int dots,
  }) {
    if (dots <= 0) return;
    g.setColor(_ink);
    for (var i = 0; i < dots; i++) {
      g.drawEllipse(
        x + (i * ScoreNotationMetrics.dotSpacing * _scale),
        y - ScoreNotationMetrics.dotYOffset * _scale,
        ScoreNotationMetrics.dotRadius * _scale,
        ScoreNotationMetrics.dotRadius * _scale,
      );
      g.fillPath();
    }
  }

  void _drawRotatedOval(
    PdfGraphics g, {
    required double x,
    required double y,
    required double width,
    required double height,
    required bool fill,
  }) {
    const k = 0.5522847498307936;
    const angle = ScoreNotationMetrics.noteheadRotation;
    final hw = width / 2;
    final hh = height / 2;

    _PdfPoint p(double dx, double dy) =>
        _rotatedEditorPoint(x: x, y: y, dx: dx, dy: dy, angle: angle);

    final top = p(0, -hh);
    final right = p(hw, 0);
    final bottom = p(0, hh);
    final left = p(-hw, 0);

    g.setColor(_ink);
    g.moveTo(top.x, top.y);
    final c1 = p(k * hw, -hh);
    final c2 = p(hw, -k * hh);
    g.curveTo(c1.x, c1.y, c2.x, c2.y, right.x, right.y);
    final c3 = p(hw, k * hh);
    final c4 = p(k * hw, hh);
    g.curveTo(c3.x, c3.y, c4.x, c4.y, bottom.x, bottom.y);
    final c5 = p(-k * hw, hh);
    final c6 = p(-hw, k * hh);
    g.curveTo(c5.x, c5.y, c6.x, c6.y, left.x, left.y);
    final c7 = p(-hw, -k * hh);
    final c8 = p(-k * hw, -hh);
    g.curveTo(c7.x, c7.y, c8.x, c8.y, top.x, top.y);

    if (fill) {
      g.fillPath();
    } else {
      g.setLineWidth(ScoreNotationMetrics.openNoteStrokeWidth * _scale);
      g.strokePath();
    }
  }

  _PdfPoint _pdfOffset(double x, double y, double dx, double dy) {
    return _PdfPoint(x + dx * _scale, y - dy * _scale);
  }

  _PdfPoint _rotatedEditorPoint({
    required double x,
    required double y,
    required double dx,
    required double dy,
    required double angle,
  }) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final rotatedX = dx * cosA - dy * sinA;
    final rotatedYDown = dx * sinA + dy * cosA;
    return _PdfPoint(x + rotatedX, y - rotatedYDown);
  }

  void _moveToOffset(PdfGraphics g, double x, double y, double dx, double dy) {
    final p = _pdfOffset(x, y, dx, dy);
    g.moveTo(p.x, p.y);
  }

  void _lineToOffset(PdfGraphics g, double x, double y, double dx, double dy) {
    final p = _pdfOffset(x, y, dx, dy);
    g.lineTo(p.x, p.y);
  }

  void _quadraticCurveTo(
    PdfGraphics g, {
    required double fromX,
    required double fromY,
    required double controlX,
    required double controlY,
    required double endX,
    required double endY,
  }) {
    g.curveTo(
      fromX + (controlX - fromX) * 2 / 3,
      fromY + (controlY - fromY) * 2 / 3,
      endX + (controlX - endX) * 2 / 3,
      endY + (controlY - endY) * 2 / 3,
      endX,
      endY,
    );
  }

  // ── Clef ──────────────────────────────────────────────────────────────────

  void _drawTrebleClef(
    PdfGraphics g,
    PdfFont musicFont,
    double x,
    double staffTop,
  ) {
    _text(
      g,
      musicFont,
      ScoreNotationMetrics.trebleClefFontSize * _scale,
      ScoreNotationMetrics.trebleClefGlyph,
      x,
      staffTop - 16 * _scale,
    );
  }

  void _drawBassClef(
    PdfGraphics g,
    double x,
    double staffTop,
    double staffBottom,
  ) {
    final cx = x + 10 * _scale;
    // Bass clef body centered on F3 (4th line from bottom = staffBottom + 3*ls)
    final f3y = staffBottom + _ls * 3;

    g.setColor(_ink);
    g.setLineWidth(ScoreNotationMetrics.bassClefStrokeWidth * _scale);

    g.moveTo(cx, f3y + _ls * 1.5);
    g.curveTo(
      cx + 14 * _scale,
      f3y + _ls * 1.5,
      cx + 18 * _scale,
      f3y + _ls * 0.5,
      cx + 12 * _scale,
      f3y,
    );
    g.curveTo(
      cx + 6 * _scale,
      f3y - _ls * 0.4,
      cx - 2 * _scale,
      f3y - _ls * 0.8,
      cx - 6 * _scale,
      f3y - _ls * 2,
    );
    g.strokePath();

    // Two dots to the right of the curl
    final dotX = cx + 20 * _scale;
    g.drawEllipse(
      dotX,
      f3y + _ls * 0.6,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
    );
    g.fillPath();
    g.drawEllipse(
      dotX,
      f3y - _ls * 0.4,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
      ScoreNotationMetrics.bassClefDotRadius * _scale,
    );
    g.fillPath();
  }

  void _drawCClef(
    PdfGraphics g,
    double x,
    double staffTop,
    double staffBottom, {
    required int clefLine,
  }) {
    final targetY = staffBottom + (clefLine - 1) * _ls;

    g.setColor(_ink);

    // Left vertical bar (spine) — drawn as a thick stroke
    g.setLineWidth(ScoreNotationMetrics.cClefSpineWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale / 2, staffTop);
    g.lineTo(
      x + ScoreNotationMetrics.cClefSpineWidth * _scale / 2,
      staffBottom,
    );
    g.strokePath();

    // Upper bracket: horizontal then vertical down to targetY
    g.setLineWidth(ScoreNotationMetrics.cClefBracketStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, staffTop);
    g.lineTo(x + 14 * _scale, staffTop);
    g.strokePath();

    g.setLineWidth(ScoreNotationMetrics.cClefVerticalStrokeWidth * _scale);
    g.moveTo(x + 14 * _scale, staffTop);
    g.lineTo(x + 14 * _scale, targetY);
    g.strokePath();

    // Lower bracket: horizontal then vertical up to targetY
    g.setLineWidth(ScoreNotationMetrics.cClefBracketStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, staffBottom);
    g.lineTo(x + 14 * _scale, staffBottom);
    g.strokePath();

    g.setLineWidth(ScoreNotationMetrics.cClefVerticalStrokeWidth * _scale);
    g.moveTo(x + 14 * _scale, targetY);
    g.lineTo(x + 14 * _scale, staffBottom);
    g.strokePath();

    // Centre line at the target staff line
    g.setLineWidth(ScoreNotationMetrics.cClefCenterStrokeWidth * _scale);
    g.moveTo(x + ScoreNotationMetrics.cClefSpineWidth * _scale, targetY);
    g.lineTo(x + 12 * _scale, targetY);
    g.strokePath();
  }

  // ── Key signature ──────────────────────────────────────────────────────────

  double _drawKeySignature(
    PdfGraphics g,
    PdfFont font,
    double x,
    int fifths, {
    required double staffBottom,
    required String clefSign,
    int clefLine = 2,
  }) {
    if (fifths == 0) return x;
    final isSharp = fifths > 0;
    final count = fifths.abs().clamp(0, 7);

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
      final y = _yForPitch(
        step: pitch.$1,
        octave: pitch.$2,
        bottomLineY: staffBottom,
        clefSign: clefSign,
        clefLine: clefLine,
      );
      _text(
        g,
        font,
        ScoreNotationMetrics.keySignatureFontSize * _scale,
        isSharp
            ? ScoreNotationMetrics.sharpGlyph
            : ScoreNotationMetrics.flatGlyph,
        x,
        y - ScoreNotationMetrics.keySignatureYOffset * _scale,
      );
      x += ScoreNotationMetrics.keySignatureSpacing * _scale;
    }
    return x;
  }

  // ── Time signature ─────────────────────────────────────────────────────────

  void _drawTimeSig(
    PdfGraphics g,
    PdfFont font,
    double x,
    double staffTop,
    int beats,
    int beatType,
  ) {
    _text(
      g,
      font,
      ScoreNotationMetrics.timeSignatureFontSize * _scale,
      '$beats',
      x,
      staffTop - 18 * _scale,
    );
    _text(
      g,
      font,
      ScoreNotationMetrics.timeSignatureFontSize * _scale,
      '$beatType',
      x,
      staffTop -
          ScoreNotationMetrics.timeSignatureBottomOffsetSpaces * _ls -
          18 * _scale,
    );
  }

  // ── Primitive helpers ──────────────────────────────────────────────────────

  void _line(
    PdfGraphics g,
    double x1,
    double y1,
    double x2,
    double y2,
    double w,
  ) {
    g.setColor(_ink);
    g.setLineWidth(w);
    g.moveTo(x1, y1);
    g.lineTo(x2, y2);
    g.strokePath();
  }

  void _text(
    PdfGraphics g,
    PdfFont font,
    double size,
    String text,
    double x,
    double y,
  ) {
    g.setColor(_ink);
    g.drawString(font, size, text, x, y);
  }

  int _visualSlotCount(List<dynamic> symbols) {
    var count = 0;
    for (final symbol in symbols) {
      if (symbol is Note && symbol.isChordTone) {
        continue;
      }
      count++;
    }
    return math.max(count, 1);
  }

  int _visualSlotForIndex(List<dynamic> symbols, int index) {
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

  static String _clefSign(List<Measure> measures) {
    for (final m in measures) {
      if (m.clef != null) return m.clef!.sign;
    }
    return 'G';
  }

  static int _clefLine(List<Measure> measures) {
    for (final m in measures) {
      if (m.clef != null) return m.clef!.line;
    }
    return 2;
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _PageData {
  const _PageData({
    required this.firstMeasureIndex,
    required this.measureCount,
    required this.measuresPerSystem,
    required this.rowsPerPage,
  });

  final int firstMeasureIndex;
  final int measureCount;
  final int measuresPerSystem;
  final int rowsPerPage;
}

class PdfPageLayoutInfo {
  const PdfPageLayoutInfo({
    required this.firstMeasureIndex,
    required this.measureCount,
    required this.measuresPerSystem,
    required this.rowsPerPage,
  });

  final int firstMeasureIndex;
  final int measureCount;
  final int measuresPerSystem;
  final int rowsPerPage;
}

class _PdfPoint {
  const _PdfPoint(this.x, this.y);

  final double x;
  final double y;
}
