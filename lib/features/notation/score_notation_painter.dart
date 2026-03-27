import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';

import 'notation_layout.dart';

/// [ScoreNotationPainter] renders a [Score] as traditional staff notation.
///
/// Layout model:
///   • One horizontal row per part, per measure group.
///   • Each row contains: left barline → clef (row 0 only) → key sig →
///     time sig → measures → right barline.
///   • Y origin of each row = rowIndex * rowHeight + staffPadTop (top staff line).
///
/// Coordinate system:
///   • (0, 0) is top-left of the canvas.
///   • staffY(row) returns the Y of the top staff line for that row.
class ScoreNotationPainter extends CustomPainter {
  final Score score;
  final Part part;
  final double totalWidth;

  ScoreNotationPainter({
    required this.score,
    required this.part,
    required this.totalWidth,
  });

  // ── Paints ────────────────────────────────────────────────────────────────

  late final Paint _staffPaint = Paint()
    ..color = NotationLayout.staffColor
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;

  late final Paint _inkPaint = Paint()
    ..color = NotationLayout.inkColor
    ..style = PaintingStyle.fill;

  late final Paint _inkStrokePaint = Paint()
    ..color = NotationLayout.inkColor
    ..strokeWidth = NotationLayout.stemWidth
    ..style = PaintingStyle.stroke;

  late final Paint _barlinePaint = Paint()
    ..color = NotationLayout.inkColor
    ..strokeWidth = NotationLayout.barlineWidth
    ..style = PaintingStyle.stroke;

  // ── Entry point ───────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (part.measures.isEmpty) return;

    double x = 0;

    for (int mi = 0; mi < part.measures.length; mi++) {
      final measure = part.measures[mi];
      final isFirst = mi == 0;
      final measureWidth = _measureWidth(measure, isFirst);
      final staffY = NotationLayout.staffPadTop;

      // Draw staff lines for this measure
      _drawStaff(canvas, x, staffY, measureWidth);

      // Clef, key sig, time sig on first measure only
      double innerX = x + NotationLayout.barlineWidth;
      if (isFirst) {
        _drawTrebleClef(canvas, innerX + 4, staffY);
        innerX += NotationLayout.clefWidth;

        final keyFifths = measure.keySignature?.fifths ?? 0;
        if (keyFifths != 0) {
          _drawKeySignature(canvas, innerX, staffY, keyFifths);
          innerX += NotationLayout.keySigWidth *
              keyFifths.abs().clamp(0, 7).toDouble() +
              4;
        }

        final ts = measure.timeSignature;
        if (ts != null) {
          _drawTimeSignature(canvas, innerX, staffY, ts.beats, ts.beatType);
          innerX += NotationLayout.timeSigWidth + 4;
        }
      }

      // Measure number
      _drawMeasureNumber(canvas, x + 4, staffY - 14, measure.number);

      // Left barline
      _drawBarline(canvas, x, staffY);

      // Symbols
      innerX += NotationLayout.measurePadL;
      for (final symbol in measure.symbols) {
        if (symbol is Note) {
          _drawNote(canvas, innerX, staffY, symbol);
          innerX += NotationLayout.noteSpacing;
        } else if (symbol is Rest) {
          _drawRest(canvas, innerX, staffY, symbol);
          innerX += NotationLayout.noteSpacing;
        }
      }

      // Right barline (double at last measure)
      final isLast = mi == part.measures.length - 1;
      _drawBarline(canvas, x + measureWidth, staffY, isDouble: isLast);

      x += measureWidth;
    }
  }

  // ── Staff ─────────────────────────────────────────────────────────────────

  double _measureWidth(Measure measure, bool isFirst) {
    double headerW = isFirst
        ? NotationLayout.clefWidth + NotationLayout.timeSigWidth + 8
        : 0;
    final keyFifths = measure.keySignature?.fifths ?? 0;
    if (isFirst && keyFifths != 0) {
      headerW += NotationLayout.keySigWidth * keyFifths.abs().clamp(0, 7) + 4;
    }
    final symbolW = measure.symbols.length * NotationLayout.noteSpacing;
    return math.max(
      NotationLayout.measureMinWidth,
      headerW + symbolW + NotationLayout.measurePadL + NotationLayout.measurePadR,
    );
  }

  void _drawStaff(Canvas canvas, double x, double staffY, double width) {
    for (int line = 0; line < 5; line++) {
      final y = staffY + line * NotationLayout.lineSpacing;
      canvas.drawLine(Offset(x, y), Offset(x + width, y), _staffPaint);
    }
  }

  void _drawBarline(Canvas canvas, double x, double staffY,
      {bool isDouble = false}) {
    canvas.drawLine(
      Offset(x, staffY),
      Offset(x, staffY + NotationLayout.staffHeight),
      _barlinePaint,
    );
    if (isDouble) {
      canvas.drawLine(
        Offset(x + 3, staffY),
        Offset(x + 3, staffY + NotationLayout.staffHeight),
        _barlinePaint,
      );
    }
  }

  // ── Measure number ────────────────────────────────────────────────────────

  void _drawMeasureNumber(Canvas canvas, double x, double y, int number) {
    _drawText(
      canvas,
      '$number',
      Offset(x, y),
      fontSize: 9,
      color: NotationLayout.measureNumColor,
    );
  }

  // ── Treble clef ───────────────────────────────────────────────────────────

  /// Draws a proper G (treble) clef using a scale-and-translate approach.
  ///
  /// The clef is constructed in a normalized coordinate space and then
  /// transformed to fit the staff. Key anchors:
  ///   • The G-line curl wraps around the second staff line from bottom (G4).
  ///   • The tall stem rises ~2 spaces above the top staff line.
  ///   • The bottom curl sits just below the bottom staff line.
  void _drawTrebleClef(Canvas canvas, double x, double staffY) {
    // Anchor points derived from staff geometry
    final gLineY  = staffY + PitchToSlot.slotToY(2); // G4 = 2nd line from bottom
    final topY    = staffY - NotationLayout.lineSpacing * 1.4; // slightly above staff
    final botY    = staffY + NotationLayout.staffHeight + NotationLayout.lineSpacing * 0.5;

    final paint = Paint()
      ..color = NotationLayout.inkColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── 1. Long vertical spine ──────────────────────────────────────────────
    final spine = Path();
    spine.moveTo(x + 5, botY);
    spine.cubicTo(
      x + 5, botY - 4,
      x + 5, topY + 4,
      x + 5, topY,
    );
    canvas.drawPath(spine, paint);

    // ── 2. Top curl — sweeps right then loops back left and down ────────────
    final topCurl = Path();
    topCurl.moveTo(x + 5, topY);
    topCurl.cubicTo(
      x + 13, topY + 1,       // right
      x + 15, topY + 7,       // top-right
      x + 12, topY + 13,      // coming back left
    );
    topCurl.cubicTo(
      x + 9,  topY + 18,
      x + 5,  topY + 20,
      x + 4,  topY + 24,      // merges back toward body
    );
    canvas.drawPath(topCurl, paint);

    // ── 3. Body loop — oval wrapping around G4 line ─────────────────────────
    final bodyLoop = Path();
    // Start from where top curl ends, flow into the oval
    bodyLoop.moveTo(x + 4, topY + 24);
    bodyLoop.cubicTo(
      x + 1,  gLineY - 10,    // left descent
      x - 7,  gLineY - 2,     // left of oval
      x - 6,  gLineY + 5,     // bottom-left
    );
    bodyLoop.cubicTo(
      x - 5,  gLineY + 13,    // bottom
      x + 4,  gLineY + 16,    // bottom-right
      x + 12, gLineY + 11,    // right
    );
    bodyLoop.cubicTo(
      x + 18, gLineY + 5,     // top-right
      x + 17, gLineY - 8,     // top
      x + 10, gLineY - 12,    // top-left
    );
    bodyLoop.cubicTo(
      x + 5,  gLineY - 15,    // closes back near stem
      x + 4,  gLineY - 8,
      x + 5,  gLineY - 2,     // back to stem crossing G line
    );
    canvas.drawPath(bodyLoop, paint);

    // ── 4. Bottom scroll ────────────────────────────────────────────────────
    final scroll = Path();
    scroll.moveTo(x + 5, botY);
    scroll.cubicTo(
      x + 11, botY,
      x + 13, botY + 4,
      x + 9,  botY + 6,
    );
    scroll.cubicTo(
      x + 5,  botY + 8,
      x + 2,  botY + 6,
      x + 3,  botY + 3,
    );
    canvas.drawPath(scroll, paint);
  }

  // ── Key signature ─────────────────────────────────────────────────────────

  // Sharp positions (slots) in treble clef order: F5, C5, G5, D5, A4, E5, B4
  static const _sharpSlots = [7, 5, 9, 6, 3, 8, 4];
  // Flat positions: B4, E5, A4, D5, G4, C5, F4
  static const _flatSlots  = [4, 7, 3, 6, 2, 5, 1];

  void _drawKeySignature(Canvas canvas, double x, double staffY, int fifths) {
    final slots = fifths > 0 ? _sharpSlots : _flatSlots;
    final count = fifths.abs().clamp(0, 7);
    for (int i = 0; i < count; i++) {
      final noteY = staffY + PitchToSlot.slotToY(slots[i]);
      _drawText(
        canvas,
        fifths > 0 ? '♯' : '♭',
        Offset(x + i * NotationLayout.keySigWidth, noteY - 8),
        fontSize: 12,
      );
    }
  }

  // ── Time signature ────────────────────────────────────────────────────────

  void _drawTimeSignature(
      Canvas canvas, double x, double staffY, int beats, int beatType) {
    final midY = staffY + NotationLayout.staffHeight / 2;
    _drawText(canvas, '$beats',     Offset(x, midY - 12), fontSize: 14, bold: true);
    _drawText(canvas, '$beatType',  Offset(x, midY),       fontSize: 14, bold: true);
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  void _drawNote(Canvas canvas, double x, double staffY, Note note) {
    final slotNum = PitchToSlot.slot(note.step, note.octave);
    final noteY   = staffY + PitchToSlot.slotToY(slotNum);
    final up      = PitchToSlot.stemUp(slotNum);
    final type    = note.type.toLowerCase();

    // Ledger lines
    for (final ls in PitchToSlot.ledgerSlotsFor(slotNum)) {
      final ly = staffY + PitchToSlot.slotToY(ls);
      canvas.drawLine(
        Offset(x - NotationLayout.ledgerW, ly),
        Offset(x + NotationLayout.ledgerW, ly),
        _inkStrokePaint,
      );
    }

    // Notehead
    final isOpen  = type == 'half';
    final isWhole = type == 'whole';
    _drawNotehead(canvas, x, noteY, isOpen: isOpen || isWhole, isWhole: isWhole);

    // Stem (not for whole notes)
    if (!isWhole) {
      _drawStem(canvas, x, noteY, up);
    }

    // Flag (eighth notes)
    if (type == 'eighth') {
      _drawFlag(canvas, x, noteY, up);
    }

    // Accidental
    if (note.alter != null && note.alter != 0) {
      final accidental = note.alter! > 0 ? '♯' : '♭';
      _drawText(canvas, accidental,
          Offset(x - 12, noteY - 8), fontSize: 10);
    }
  }

  void _drawNotehead(Canvas canvas, double cx, double cy,
      {required bool isOpen, required bool isWhole}) {
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: NotationLayout.noteheadW,
      height: NotationLayout.noteheadH,
    );

    if (isWhole) {
      // Whole note: open oval with hole in center
      canvas.drawOval(rect, _inkStrokePaint..strokeWidth = 1.5);
    } else if (isOpen) {
      // Half note: open oval
      canvas.drawOval(rect, _inkPaint);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: NotationLayout.noteheadW - 3,
          height: NotationLayout.noteheadH - 3,
        ),
        Paint()..color = const Color(0xFF141414)..style = PaintingStyle.fill,
      );
      canvas.drawOval(rect, _inkStrokePaint..strokeWidth = 1.2);
    } else {
      // Filled notehead (quarter, eighth, sixteenth…)
      canvas.drawOval(rect, _inkPaint);
    }
  }

  void _drawStem(Canvas canvas, double cx, double noteY, bool up) {
    final xOffset = up
        ? NotationLayout.noteheadW / 2 - 0.5
        : -NotationLayout.noteheadW / 2 + 0.5;
    final stemEndY = up
        ? noteY - NotationLayout.stemLength
        : noteY + NotationLayout.stemLength;
    canvas.drawLine(
      Offset(cx + xOffset, noteY),
      Offset(cx + xOffset, stemEndY),
      _inkStrokePaint..strokeWidth = NotationLayout.stemWidth,
    );
  }

  void _drawFlag(Canvas canvas, double cx, double noteY, bool up) {
    final xOffset = up
        ? NotationLayout.noteheadW / 2 - 0.5
        : -NotationLayout.noteheadW / 2 + 0.5;
    final stemTopY = up
        ? noteY - NotationLayout.stemLength
        : noteY + NotationLayout.stemLength;

    final path = Path();
    if (up) {
      path.moveTo(cx + xOffset, stemTopY);
      path.cubicTo(
        cx + xOffset + NotationLayout.flagWidth, stemTopY + 6,
        cx + xOffset + NotationLayout.flagWidth, stemTopY + 14,
        cx + xOffset,                            stemTopY + 18,
      );
    } else {
      path.moveTo(cx + xOffset, stemTopY);
      path.cubicTo(
        cx + xOffset - NotationLayout.flagWidth, stemTopY - 6,
        cx + xOffset - NotationLayout.flagWidth, stemTopY - 14,
        cx + xOffset,                            stemTopY - 18,
      );
    }
    canvas.drawPath(path, _inkStrokePaint..strokeWidth = 1.4);
  }

  // ── Rests ─────────────────────────────────────────────────────────────────

  void _drawRest(Canvas canvas, double x, double staffY, Rest rest) {
    final type = rest.type.toLowerCase();

    switch (type) {
      case 'whole':
        _drawWholeRest(canvas, x, staffY);
      case 'half':
        _drawHalfRest(canvas, x, staffY);
      case 'quarter':
        _drawQuarterRest(canvas, x, staffY);
      case 'eighth':
        _drawEighthRest(canvas, x, staffY);
      default:
        // Fallback: draw a quarter rest for unknown types
        _drawQuarterRest(canvas, x, staffY);
    }
  }

  /// Whole rest: filled rectangle hanging under line 4 (slot 6).
  void _drawWholeRest(Canvas canvas, double x, double staffY) {
    final line4Y = staffY + NotationLayout.lineSpacing; // line 4 from top
    canvas.drawRect(
      Rect.fromLTWH(x - 6, line4Y, 12, NotationLayout.slotHeight),
      _inkPaint,
    );
  }

  /// Half rest: filled rectangle sitting on line 3 (middle line, slot 4).
  void _drawHalfRest(Canvas canvas, double x, double staffY) {
    final line3Y = staffY + NotationLayout.lineSpacing * 2; // middle line
    canvas.drawRect(
      Rect.fromLTWH(x - 6, line3Y - NotationLayout.slotHeight,
          12, NotationLayout.slotHeight),
      _inkPaint,
    );
  }

  /// Quarter rest: squiggly shape approximated with curves.
  void _drawQuarterRest(Canvas canvas, double x, double staffY) {
    final midY = staffY + NotationLayout.staffHeight / 2;
    final path = Path();
    path.moveTo(x + 2, midY - 12);
    path.cubicTo(x + 8, midY - 8, x - 4, midY - 4, x + 4, midY);
    path.cubicTo(x + 8, midY + 4, x,     midY + 8, x + 2, midY + 12);
    canvas.drawPath(path, _inkStrokePaint..strokeWidth = 1.6);
  }

  /// Eighth rest: small flag shape.
  void _drawEighthRest(Canvas canvas, double x, double staffY) {
    final midY = staffY + NotationLayout.staffHeight / 2;
    // Dot
    canvas.drawCircle(Offset(x + 2, midY - 4), 2.5, _inkPaint);
    // Stem down
    canvas.drawLine(
      Offset(x + 2, midY - 4),
      Offset(x - 2, midY + 8),
      _inkStrokePaint..strokeWidth = 1.4,
    );
  }

  // ── Text helper ───────────────────────────────────────────────────────────

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    double fontSize = 11,
    Color color = NotationLayout.inkColor,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  // ── Total canvas width computation ────────────────────────────────────────

  /// Computes the total canvas width needed to render all measures.
  static double computeWidth(Part part) {
    if (part.measures.isEmpty) return 300;
    double total = 0;
    for (int i = 0; i < part.measures.length; i++) {
      final m = part.measures[i];
      final isFirst = i == 0;
      double headerW = isFirst
          ? NotationLayout.clefWidth + NotationLayout.timeSigWidth + 8
          : 0;
      final keyFifths = m.keySignature?.fifths ?? 0;
      if (isFirst && keyFifths != 0) {
        headerW += NotationLayout.keySigWidth * keyFifths.abs().clamp(0, 7) + 4;
      }
      final symbolW = m.symbols.length * NotationLayout.noteSpacing;
      total += math.max(
        NotationLayout.measureMinWidth,
        headerW + symbolW + NotationLayout.measurePadL + NotationLayout.measurePadR,
      );
    }
    return total + NotationLayout.barlineWidth * 2;
  }

  @override
  bool shouldRepaint(ScoreNotationPainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.part != part;
}