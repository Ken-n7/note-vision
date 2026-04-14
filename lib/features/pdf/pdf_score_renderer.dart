import 'dart:math' as math;
import 'dart:typed_data';

import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/staff_pitch_mapper.dart';
import 'package:pdf/pdf.dart';

/// Renders a [Score] as an engraved A4 PDF and returns the raw bytes.
///
/// Uses the same pitch-to-position math as [ScoreNotationPainter] so that
/// the PDF output matches the editor canvas layout.
class PdfScoreRenderer {
  const PdfScoreRenderer();

  // ── Page & layout constants ──────────────────────────────────────────────
  static const double _marginPt = 20 * PdfPageFormat.mm;
  static const double _ls = 6.0; // staff line spacing in pt
  static const double _staffH = _ls * 4; // top-to-bottom of 5-line staff
  static const double _sysSp = 40.0; // gap between bottom of one system and top of next
  static const double _prefixW = 52.0; // clef + key/time sig area
  static const double _mw = 90.0; // min measure width
  static const double _titleBlockH = 46.0; // reserved at top of first page

  // Notehead semi-axes scaled proportionally to _ls (editor uses hw=6.25, hh=4.4 at ls=12)
  static const double _nhw = 3.1;       // non-whole semi-major
  static const double _nhh = 2.2;       // non-whole semi-minor
  static const double _nhwWhole = 3.5;  // whole semi-major
  static const double _nhhWhole = 2.5;  // whole semi-minor

  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns raw PDF bytes for [score].
  Future<Uint8List> render(Score score) async {
    final doc = PdfDocument();
    final font = PdfFont.courier(doc);
    final fontBold = PdfFont.courierBold(doc);

    if (score.parts.isEmpty) {
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _text(g, fontBold, 14, 'Empty score', _marginPt, PdfPageFormat.a4.height - _marginPt - 14);
      return doc.save();
    }

    final pages = _paginate(score);

    for (final pageData in pages) {
      final page = PdfPage(doc, pageFormat: PdfPageFormat.a4);
      final g = page.getGraphics();
      _paintPage(g, pageData, score, font, fontBold, PdfPageFormat.a4);
    }

    return doc.save();
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  List<_PageData> _paginate(Score score) {
    final pw = PdfPageFormat.a4.width;
    final ph = PdfPageFormat.a4.height;
    final contentW = pw - _marginPt * 2;
    final partCount = score.parts.length;
    final maxMeasures =
        score.parts.fold(0, (m, p) => math.max(m, p.measures.length));
    final mps = math.max(
      1,
      ((contentW - _prefixW) / _mw).floor(),
    ); // measures per system
    final totalSystems =
        maxMeasures == 0 ? 0 : (maxMeasures / mps).ceil();
    final systemH = partCount * (_staffH + _sysSp);

    final result = <_PageData>[];
    var si = 0;
    var firstPage = true;

    while (si < totalSystems) {
      final usable = ph - _marginPt * 2 - (firstPage ? _titleBlockH : 0.0);
      final sysOnPage = math.max(1, (usable / systemH).floor());
      final sysHere = math.min(sysOnPage, totalSystems - si);
      result.add(_PageData(
        firstSystemIndex: si,
        systemCount: sysHere,
        measuresPerSystem: mps,
        isFirstPage: firstPage,
      ));
      si += sysHere;
      firstPage = false;
    }

    if (result.isEmpty) {
      result.add(_PageData(
        firstSystemIndex: 0,
        systemCount: 0,
        measuresPerSystem: mps,
        isFirstPage: true,
      ));
    }
    return result;
  }

  // ── Page painter ──────────────────────────────────────────────────────────

  void _paintPage(
    PdfGraphics g,
    _PageData page,
    Score score,
    PdfFont font,
    PdfFont fontBold,
    PdfPageFormat fmt,
  ) {
    final pageH = fmt.height;
    final partCount = score.parts.length;

    // PDF y=0 is at bottom, y=pageH is top.
    var yTop = pageH - _marginPt; // current y from bottom, starts near top

    if (page.isFirstPage) {
      _drawTitleBlock(g, font, fontBold, score, fmt, yTop);
      yTop -= _titleBlockH;
    }

    for (var s = 0; s < page.systemCount; s++) {
      final si = page.firstSystemIndex + s;
      final startM = si * page.measuresPerSystem;

      for (var pi = 0; pi < partCount; pi++) {
        final part = score.parts[pi];
        if (startM >= part.measures.length) continue;

        final endM =
            math.min(startM + page.measuresPerSystem, part.measures.length);
        final rowMeasures = part.measures.sublist(startM, endM);

        // staffTop = top staff line in PDF coords (y from bottom).
        // We descend: each part shifts down by _staffH + _sysSp.
        final staffTop = yTop - pi * (_staffH + _sysSp) - _staffH;

        _drawStaffRow(
          g,
          font,
          fontBold,
          fmt,
          rowMeasures: rowMeasures,
          staffTop: staffTop,
          startMeasureGlobal: startM,
          clefSign: _clefSign(rowMeasures),
          isFirstSystem: si == 0,
        );
      }

      // Advance yTop past this system
      yTop -= partCount * (_staffH + _sysSp);
    }
  }

  // ── Title block ────────────────────────────────────────────────────────────

  void _drawTitleBlock(
    PdfGraphics g,
    PdfFont font,
    PdfFont fontBold,
    Score score,
    PdfPageFormat fmt,
    double yTop,
  ) {
    final title = score.title.isEmpty ? 'Untitled Score' : score.title;
    _text(g, fontBold, 16, title, _marginPt, yTop - 20);

    if (score.composer.isNotEmpty) {
      final compW = _strWidth(score.composer, 9);
      _text(g, font, 9, score.composer,
          fmt.width - _marginPt - compW, yTop - 36);
    }
  }

  // ── Staff row ──────────────────────────────────────────────────────────────

  void _drawStaffRow(
    PdfGraphics g,
    PdfFont font,
    PdfFont fontBold,
    PdfPageFormat fmt, {
    required List<Measure> rowMeasures,
    required double staffTop,
    required int startMeasureGlobal,
    required String clefSign,
    required bool isFirstSystem,
  }) {
    // staffTop = y of top staff line (PDF: y from bottom)
    // staffBottom = y of bottom staff line
    final staffBottom = staffTop - _staffH;
    final contentStartX = _marginPt + _prefixW;
    final staffEndX = contentStartX + rowMeasures.length * _mw;

    // 5 staff lines
    for (var i = 0; i < 5; i++) {
      final lineY = staffTop - i * _ls;
      _line(g, _marginPt, lineY, staffEndX, lineY, 0.5);
    }

    // Opening barline
    _line(g, contentStartX, staffTop, contentStartX, staffBottom, 0.8);
    // Closing barline
    _line(g, staffEndX, staffTop, staffEndX, staffBottom, 0.8);

    // Clef
    if (clefSign.toUpperCase() == 'F') {
      _drawBassClef(g, _marginPt + 4, staffTop, staffBottom);
    } else {
      _drawTrebleClef(g, _marginPt + 6, staffTop, staffBottom);
    }

    // Key + time signature (first system only)
    var sigX = _marginPt + 28.0;
    if (isFirstSystem && rowMeasures.isNotEmpty) {
      final first = rowMeasures.first;
      if (first.keySignature != null) {
        sigX = _drawKeySignature(
          g,
          font,
          sigX,
          first.keySignature!.fifths,
          staffBottom: staffBottom,
          clefSign: clefSign,
        );
      }
      if (first.timeSignature != null) {
        _drawTimeSig(
          g,
          fontBold,
          sigX + 4,
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
        _line(g, measureStartX, staffTop, measureStartX, staffBottom, 0.7);
      }

      // Measure number
      _text(g, font, 6, '${measure.number}', measureStartX + 3,
          staffTop + 6);

      _drawMeasureSymbols(
        g,
        measure,
        measureStartX: measureStartX,
        measureEndX: measureEndX,
        staffTop: staffTop,
        staffBottom: staffBottom,
        clefSign: clefSign,
      );
    }
  }

  // ── Measure symbols ────────────────────────────────────────────────────────

  void _drawMeasureSymbols(
    PdfGraphics g,
    Measure measure, {
    required double measureStartX,
    required double measureEndX,
    required double staffTop,
    required double staffBottom,
    required String clefSign,
  }) {
    if (measure.symbols.isEmpty) return;

    const innerPad = 10.0;
    final drawableW =
        math.max(12.0, (measureEndX - measureStartX) - innerPad * 2);
    final count = measure.symbols.length;
    final middleLineY = staffTop - _ls * 2; // 3rd staff line from top

    for (var i = 0; i < count; i++) {
      final symbol = measure.symbols[i];
      final progress = (i + 1) / (count + 1);
      final x = measureStartX + innerPad + drawableW * progress;

      if (symbol is Note) {
        final y = StaffPitchMapper.yForPitch(
          step: symbol.step,
          octave: symbol.octave,
          bottomLineY: staffBottom,
          lineSpacing: _ls,
          clefSign: clefSign,
        );
        _drawNote(g, symbol,
            x: x, y: y, middleLineY: middleLineY, staffBottom: staffBottom, staffTop: staffTop);
      } else if (symbol is Rest) {
        _drawRest(g, symbol,
            x: x, staffTop: staffTop, staffBottom: staffBottom);
      }
    }
  }

  // ── Note ──────────────────────────────────────────────────────────────────

  void _drawNote(
    PdfGraphics g,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
    required double staffBottom,
    required double staffTop,
  }) {
    final type = note.type.trim().toLowerCase();
    final isWhole = type == 'whole';
    final isHalf = type == 'half';
    final isEighth = type == 'eighth';

    g.setColor(_ink);

    _ledgerLines(g, x: x, y: y, staffBottom: staffBottom, staffTop: staffTop);

    _drawNoteHead(
      g, x, y,
      hw: isWhole ? _nhwWhole : _nhw,
      hh: isWhole ? _nhhWhole : _nhh,
      filled: !(isWhole || isHalf),
    );

    if (isWhole) return;

    final stemUp = y < middleLineY;
    _drawStem(g, x: x, y: y, stemUp: stemUp, isEighth: isEighth);
  }

  /// Draws a rotated oval notehead using a 4-segment cubic bezier approximation.
  /// Matches the editor's `canvas.rotate(-0.35)` tilt visually (sign flips because
  /// PDF y-axis points up, opposite to Flutter's canvas).
  void _drawNoteHead(
    PdfGraphics g,
    double cx,
    double cy, {
    required double hw,
    required double hh,
    required bool filled,
  }) {
    const angle = 0.35; // rad — visual equivalent of editor's canvas.rotate(-0.35)
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    const k = 0.5523; // cubic bezier magic number for ellipse approximation

    // Four cardinal points on the rotated ellipse
    final rx = cx + hw * cosA;  final ry = cy + hw * sinA;
    final tx = cx - hh * sinA;  final ty = cy + hh * cosA;
    final lx = cx - hw * cosA;  final ly = cy - hw * sinA;
    final bx = cx + hh * sinA;  final by_ = cy - hh * cosA;

    // Bezier curves: each segment uses the derivative of the parametric ellipse
    // scaled by k to control the "pull" of the handles.
    g.moveTo(rx, ry);
    g.curveTo(
      cx + hw * cosA - k * hh * sinA, cy + hw * sinA + k * hh * cosA,
      cx - hh * sinA + k * hw * cosA, cy + hh * cosA + k * hw * sinA,
      tx, ty,
    );
    g.curveTo(
      cx - hh * sinA - k * hw * cosA, cy + hh * cosA - k * hw * sinA,
      cx - hw * cosA - k * hh * sinA, cy - hw * sinA + k * hh * cosA,
      lx, ly,
    );
    g.curveTo(
      cx - hw * cosA + k * hh * sinA, cy - hw * sinA - k * hh * cosA,
      cx + hh * sinA - k * hw * cosA, cy - hh * cosA - k * hw * sinA,
      bx, by_,
    );
    g.curveTo(
      cx + hh * sinA + k * hw * cosA, cy - hh * cosA + k * hw * sinA,
      cx + hw * cosA + k * hh * sinA, cy + hw * sinA - k * hh * cosA,
      rx, ry,
    );

    g.setColor(_ink);
    if (filled) {
      g.fillPath();
    } else {
      g.setLineWidth(0.9);
      g.strokePath();
    }
  }

  void _ledgerLines(
    PdfGraphics g, {
    required double x,
    required double y,
    required double staffBottom,
    required double staffTop,
  }) {
    const hw = 7.0;
    g.setColor(_ink);
    g.setLineWidth(0.5);

    // Below staff
    for (var i = 1; i <= 4; i++) {
      final lineY = staffBottom - i * _ls;
      if (y <= lineY + 0.5) {
        _line(g, x - hw, lineY, x + hw, lineY, 0.5);
      }
    }
    // Above staff
    for (var i = 1; i <= 4; i++) {
      final lineY = staffTop + i * _ls;
      if (y >= lineY - 0.5) {
        _line(g, x - hw, lineY, x + hw, lineY, 0.5);
      }
    }
  }

  void _drawStem(
    PdfGraphics g, {
    required double x,
    required double y,
    required bool stemUp,
    required bool isEighth,
  }) {
    final stemLen = _ls * 3.5;
    final stemX = stemUp ? x + _nhw : x - _nhw;
    final endY = stemUp ? y + stemLen : y - stemLen;

    g.setColor(_ink);
    _line(g, stemX, y, stemX, endY, 0.8);

    if (!isEighth) return;

    // Flag
    g.setLineWidth(0.9);
    g.setColor(_ink);
    if (stemUp) {
      g.moveTo(stemX, endY);
      g.curveTo(stemX + 7, endY - 1, stemX + 5, endY - 6, stemX + 1, endY - 9);
    } else {
      g.moveTo(stemX, endY);
      g.curveTo(stemX - 7, endY + 1, stemX - 5, endY + 6, stemX - 1, endY + 9);
    }
    g.strokePath();
  }

  // ── Rest ──────────────────────────────────────────────────────────────────

  void _drawRest(
    PdfGraphics g,
    Rest rest, {
    required double x,
    required double staffTop,
    required double staffBottom,
  }) {
    final type = rest.type.trim().toLowerCase();
    g.setColor(_ink);

    if (type == 'whole') {
      // Rectangle hanging below line 4 (from top)
      final lineY = staffTop - _ls * 3;
      g.drawRect(x - 6.5, lineY - 3.5, 13, 3.5);
      g.fillPath();
      return;
    }

    if (type == 'half') {
      // Rectangle sitting on line 3 (from top)
      final lineY = staffTop - _ls * 2;
      g.drawRect(x - 6.5, lineY, 13, 3.5);
      g.fillPath();
      return;
    }

    // Quarter rest — zigzag
    final qy = staffTop - _ls * 1.4;
    g.setLineWidth(0.9);
    g.moveTo(x - 2, qy);
    g.lineTo(x + 2.5, qy + 2);
    g.lineTo(x - 1.5, qy + 4.5);
    g.lineTo(x + 2.5, qy + 7);
    g.lineTo(x - 1, qy + 9);
    g.lineTo(x + 2.5, qy + 12);
    g.lineTo(x - 3, qy + 14);
    g.strokePath();
  }

  // ── Clef ──────────────────────────────────────────────────────────────────

  void _drawTrebleClef(
      PdfGraphics g, double x, double staffTop, double staffBottom) {
    final cx = x + 7.0;
    final g4y = staffBottom + _ls; // G4 = 2nd line from bottom

    g.setColor(_ink);
    g.setLineWidth(1.2);

    // ── Spine ─────────────────────────────────────────────────────────────
    // Runs from below the staff up through the body to above the staff with
    // a subtle S-curve (bows right mid-staff, straightens at top).
    final spineBot = staffBottom - _ls * 0.9;
    final spineTop = staffTop + _ls * 1.5;
    g.moveTo(cx, spineBot);
    g.curveTo(
      cx + _ls * 0.6, staffBottom + _ls * 0.5,   // bulges right low
      cx - _ls * 0.2, staffTop - _ls * 0.5,       // eases left near top
      cx, spineTop,
    );
    g.strokePath();

    // ── Body: D-shaped loop encircling G4 ─────────────────────────────────
    // Open on the left where the spine exits; bulges right.
    final loopTop = g4y + _ls * 1.8;
    final loopBot = g4y - _ls * 1.5;
    g.moveTo(cx, loopTop);
    g.curveTo(
      cx + _ls * 2.2, loopTop,
      cx + _ls * 2.4, loopBot,
      cx, loopBot,
    );
    g.curveTo(
      cx - _ls * 0.7, loopBot,
      cx - _ls * 0.8, g4y - _ls * 0.2,
      cx, g4y + _ls * 0.6,
    );
    g.strokePath();

    // ── Top curl ──────────────────────────────────────────────────────────
    // Sweeps right from the spine tip then hooks back left (fishhook).
    g.moveTo(cx, spineTop);
    g.curveTo(
      cx + _ls * 1.8, spineTop + _ls * 0.7,
      cx + _ls * 2.0, spineTop - _ls * 0.8,
      cx + _ls * 0.6, spineTop - _ls * 1.2,
    );
    g.strokePath();

    // ── Bottom tail: small counterclockwise loop below the staff ──────────
    g.moveTo(cx, spineBot);
    g.curveTo(
      cx + _ls * 1.6, spineBot - _ls * 0.3,
      cx + _ls * 1.6, spineBot + _ls * 1.1,
      cx + _ls * 0.3, spineBot + _ls * 1.0,
    );
    g.curveTo(
      cx - _ls * 0.5, spineBot + _ls * 0.9,
      cx - _ls * 0.6, spineBot + _ls * 0.1,
      cx, spineBot,
    );
    g.strokePath();
  }

  void _drawBassClef(
      PdfGraphics g, double x, double staffTop, double staffBottom) {
    final cx = x + 10;
    // Bass clef body centered on F3 (4th line from bottom = staffBottom + 3*ls)
    final f3y = staffBottom + _ls * 3;

    g.setColor(_ink);
    g.setLineWidth(1.1);

    g.moveTo(cx, f3y + _ls * 1.5);
    g.curveTo(cx + 12, f3y + _ls * 1.5, cx + 16, f3y + _ls * 0.5, cx + 9, f3y);
    g.curveTo(cx + 4, f3y - _ls * 0.4, cx - 2, f3y - _ls * 0.8, cx - 3, f3y - _ls * 2);
    g.strokePath();

    // Two dots to the right of the curl
    final dotX = cx + 18;
    g.drawEllipse(dotX, f3y + _ls * 0.2, 2.2, 2.2);
    g.fillPath();
    g.drawEllipse(dotX, f3y - _ls * 0.8, 2.2, 2.2);
    g.fillPath();
  }

  // ── Key signature ──────────────────────────────────────────────────────────

  double _drawKeySignature(
    PdfGraphics g,
    PdfFont font,
    double x,
    int fifths, {
    required double staffBottom,
    required String clefSign,
  }) {
    if (fifths == 0) return x;
    final isSharp = fifths > 0;
    final count = fifths.abs().clamp(0, 7);

    const sharpOrderTreble = [
      ('F', 5), ('C', 5), ('G', 5), ('D', 5), ('A', 4), ('E', 5), ('B', 4),
    ];
    const flatOrderTreble = [
      ('B', 4), ('E', 5), ('A', 4), ('D', 5), ('G', 4), ('C', 5), ('F', 4),
    ];
    const sharpOrderBass = [
      ('F', 3), ('C', 3), ('G', 3), ('D', 3), ('A', 2), ('E', 3), ('B', 2),
    ];
    const flatOrderBass = [
      ('B', 2), ('E', 3), ('A', 2), ('D', 3), ('G', 2), ('C', 3), ('F', 2),
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
        lineSpacing: _ls,
        clefSign: clefSign,
      );
      _text(g, font, 7, isSharp ? '#' : 'b', x, y + 2);
      x += 6;
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
    _text(g, font, 9, '$beats', x, staffTop - _ls * 1.2);
    _text(g, font, 9, '$beatType', x, staffTop - _ls * 3.0);
  }

  // ── Primitive helpers ──────────────────────────────────────────────────────

  void _line(PdfGraphics g, double x1, double y1, double x2, double y2, double w) {
    g.setColor(_ink);
    g.setLineWidth(w);
    g.moveTo(x1, y1);
    g.lineTo(x2, y2);
    g.strokePath();
  }

  void _text(PdfGraphics g, PdfFont font, double size, String text, double x, double y) {
    g.setColor(_ink);
    g.drawString(font, size, text, x, y);
  }

  double _strWidth(String s, double size) => s.length * size * 0.52;

  static String _clefSign(List<Measure> measures) {
    for (final m in measures) {
      if (m.clef != null) return m.clef!.sign;
    }
    return 'G';
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _PageData {
  const _PageData({
    required this.firstSystemIndex,
    required this.systemCount,
    required this.measuresPerSystem,
    required this.isFirstPage,
  });

  final int firstSystemIndex;
  final int systemCount;
  final int measuresPerSystem;
  final bool isFirstPage;
}
