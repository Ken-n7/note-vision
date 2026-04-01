import 'package:flutter/material.dart';
import '../../../domain/model/musical_symbol.dart';

class MusicalSymbolPainter extends CustomPainter {
  final MusicalSymbol symbol;
  final Color color;
  final Color backgroundColor;

  const MusicalSymbolPainter({
    required this.symbol,
    this.color = Colors.white,
    this.backgroundColor = Colors.black,
  });

  // ── Recommended widget size ──────────────────────────────────────────
  // Use a 36×56 box, e.g.:
  //   SizedBox(
  //     width: 36, height: 56,
  //     child: CustomPaint(painter: MusicalSymbolPainter(symbol: s)),
  //   )

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // All coordinates below are authored for w=36, h=56 then scaled
    // naturally by CustomPaint — nothing hardcoded in px.

    final sp = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final fp = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final hp = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    // Helpers ────────────────────────────────────────────────────────────

    void stem(double x, double yBottom, double yTop) {
      canvas.drawLine(
        Offset(x, yBottom),
        Offset(x, yTop),
        sp..strokeWidth = w * 0.11,
      );
    }

    void openHead(Offset c, double rx, double ry, double deg) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(deg * 3.14159265 / 180);
      // Outer stroke oval
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        sp..strokeWidth = w * 0.175,
      );
      // Punch-through hole
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 0.85, height: ry * 0.6),
        hp,
      );
      canvas.restore();
    }

    void filledHead(Offset c, double rx, double ry, double deg) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(deg * 3.14159265 / 180);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        fp,
      );
      canvas.restore();
    }

    switch (symbol) {

      // ── WHOLE NOTE ──────────────────────────────────────────────────
      case MusicalSymbol.wholeNote:
        // Centred, no stem
        openHead(Offset(w * 0.50, h * 0.52), w * 0.38, h * 0.19, -13);
        break;

      // ── HALF NOTE ───────────────────────────────────────────────────
      case MusicalSymbol.halfNote:
        final cx = w * 0.38;
        final cy = h * 0.72;
        openHead(Offset(cx, cy), w * 0.36, h * 0.17, -18);
        stem(cx + w * 0.34, cy - h * 0.09, h * 0.06);
        break;

      // ── QUARTER NOTE ────────────────────────────────────────────────
      case MusicalSymbol.quarterNote:
        final cx = w * 0.38;
        final cy = h * 0.72;
        filledHead(Offset(cx, cy), w * 0.36, h * 0.17, -22);
        stem(cx + w * 0.34, cy - h * 0.07, h * 0.06);
        break;

      // ── EIGHTH NOTE ─────────────────────────────────────────────────
      case MusicalSymbol.eighthNote:
        final cx = w * 0.36;
        final cy = h * 0.72;
        filledHead(Offset(cx, cy), w * 0.34, h * 0.17, -22);
        final sx = cx + w * 0.32;
        final st = h * 0.06;
        stem(sx, cy - h * 0.07, st);
        // Flag: one clean cubic from stem top, hooks right then curls down
        final flag = Path()
          ..moveTo(sx, st)
          ..cubicTo(
            sx + w * 0.68, st + h * 0.14,
            sx + w * 0.60, st + h * 0.34,
            sx + w * 0.22, st + h * 0.44,
          );
        canvas.drawPath(flag, sp..strokeWidth = w * 0.11);
        break;

      // ── WHOLE REST ──────────────────────────────────────────────────
      case MusicalSymbol.wholeRest:
        // Thick block hanging below a line — centred vertically higher
        final rw = w * 0.68;
        final rh = h * 0.17;
        final lx = (w - rw) / 2;
        final ly = h * 0.38;
        // Ledger line
        canvas.drawLine(
          Offset(lx - w * 0.08, ly),
          Offset(lx + rw + w * 0.08, ly),
          sp..strokeWidth = w * 0.10,
        );
        // Block hangs below
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(lx, ly + w * 0.03, rw, rh),
            const Radius.circular(1.5),
          ),
          fp,
        );
        break;

      // ── HALF REST ───────────────────────────────────────────────────
      case MusicalSymbol.halfRest:
        // Thick block sitting on top of a line
        final rw = w * 0.68;
        final rh = h * 0.17;
        final lx = (w - rw) / 2;
        final ly = h * 0.56;
        // Block sits above
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(lx, ly - rh - w * 0.03, rw, rh),
            const Radius.circular(1.5),
          ),
          fp,
        );
        // Ledger line below
        canvas.drawLine(
          Offset(lx - w * 0.08, ly),
          Offset(lx + rw + w * 0.08, ly),
          sp..strokeWidth = w * 0.10,
        );
        break;

      case MusicalSymbol.quarterRest:
        final cx = w * 0.52;
        // Classic Z-squiggle: top diagonal, middle notch, tail curl
        final path = Path()
          ..moveTo(cx + w * 0.22, h * 0.10)   // top-right start
          ..lineTo(cx - w * 0.10, h * 0.30)   // diagonal down-left
          ..lineTo(cx + w * 0.20, h * 0.46)   // kick back right
          ..quadraticBezierTo(                  // curve into tail
            cx + w * 0.30, h * 0.56,
            cx + w * 0.10, h * 0.66,
          )
          ..quadraticBezierTo(                  // tail curls left
            cx - w * 0.14, h * 0.80,
            cx - w * 0.08, h * 0.90,
          );
        canvas.drawPath(path, sp..strokeWidth = w * 0.13);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant MusicalSymbolPainter oldDelegate) =>
      symbol != oldDelegate.symbol ||
      color != oldDelegate.color ||
      backgroundColor != oldDelegate.backgroundColor;
}