import 'package:flutter/material.dart';
import '../../../domain/model/musical_symbol.dart';

class MusicalSymbolPainter extends CustomPainter {
  final MusicalSymbol symbol;
  final Color color;

  MusicalSymbolPainter({
    required this.symbol,
    this.color = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // All values are relative to w/h — nothing overflows.
    final strokePaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (symbol) {
      // ── WHOLE NOTE: open oval, NO stem ──────────────────────────────────
      case MusicalSymbol.wholeNote:
        final rect = Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.58),
          width: w * 0.72,
          height: h * 0.38,
        );
        // Outer filled oval
        canvas.drawOval(rect, fillPaint);
        // Inner "hole" to create the open note appearance
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(w * 0.50, h * 0.58),
            width: w * 0.38,
            height: h * 0.18,
          ),
          Paint()
            ..color = Colors.transparent
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.fill,
        );
        // Simpler: draw as thick stroke oval
        canvas.drawOval(rect, strokePaint..strokeWidth = w * 0.09);
        break;

      // ── HALF NOTE: open oval WITH stem ──────────────────────────────────
      case MusicalSymbol.halfNote:
        final headCy = h * 0.72;
        final headRect = Rect.fromCenter(
          center: Offset(w * 0.42, headCy),
          width: w * 0.68,
          height: h * 0.34,
        );
        canvas.drawOval(headRect, strokePaint..strokeWidth = w * 0.08);

        // Stem goes up from right side of head
        final stemX = w * 0.76;
        canvas.drawLine(
          Offset(stemX, headCy - h * 0.10),
          Offset(stemX, h * 0.08),
          strokePaint..strokeWidth = w * 0.07,
        );
        break;

      // ── QUARTER NOTE: filled oval WITH stem ─────────────────────────────
      case MusicalSymbol.quarterNote:
        final headCy = h * 0.72;
        // Slightly rotated filled oval head
        canvas.save();
        canvas.translate(w * 0.42, headCy);
        canvas.rotate(-0.28);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: w * 0.68,
            height: h * 0.34,
          ),
          fillPaint,
        );
        canvas.restore();

        // Stem
        final stemX = w * 0.76;
        canvas.drawLine(
          Offset(stemX, headCy - h * 0.10),
          Offset(stemX, h * 0.08),
          strokePaint..strokeWidth = w * 0.07,
        );
        break;

      // ── EIGHTH NOTE: filled oval + stem + flag ───────────────────────────
      case MusicalSymbol.eighthNote:
        final headCy = h * 0.72;
        // Filled rotated head
        canvas.save();
        canvas.translate(w * 0.38, headCy);
        canvas.rotate(-0.28);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: w * 0.64,
            height: h * 0.32,
          ),
          fillPaint,
        );
        canvas.restore();

        // Stem
        final stemX = w * 0.70;
        final stemTop = h * 0.08;
        final stemBottom = headCy - h * 0.08;
        canvas.drawLine(
          Offset(stemX, stemBottom),
          Offset(stemX, stemTop),
          strokePaint..strokeWidth = w * 0.07,
        );

        // Flag — curves right from stem top
        final flagPath = Path()
          ..moveTo(stemX, stemTop)
          ..cubicTo(
            stemX + w * 0.38, stemTop + h * 0.12,
            stemX + w * 0.32, stemTop + h * 0.28,
            stemX + w * 0.04, stemTop + h * 0.36,
          );
        canvas.drawPath(flagPath, strokePaint..strokeWidth = w * 0.07);
        break;

      // ── WHOLE REST: filled rect hanging below an implied line ─────────────
      case MusicalSymbol.wholeRest:
        final rectW = w * 0.62;
        final rectH = h * 0.20;
        final left = (w - rectW) / 2;
        final top = h * 0.34; // hangs below mid-line
        canvas.drawRect(Rect.fromLTWH(left, top, rectW, rectH), fillPaint);
        // Line above the block
        canvas.drawLine(
          Offset(left - w * 0.06, top),
          Offset(left + rectW + w * 0.06, top),
          strokePaint..strokeWidth = w * 0.06,
        );
        break;

      // ── HALF REST: filled rect sitting ON an implied line ─────────────────
      case MusicalSymbol.halfRest:
        final rectW = w * 0.62;
        final rectH = h * 0.20;
        final left = (w - rectW) / 2;
        final top = h * 0.46; // sits above mid-line
        canvas.drawRect(Rect.fromLTWH(left, top, rectW, rectH), fillPaint);
        // Line below the block
        canvas.drawLine(
          Offset(left - w * 0.06, top + rectH),
          Offset(left + rectW + w * 0.06, top + rectH),
          strokePaint..strokeWidth = w * 0.06,
        );
        break;

      // ── QUARTER REST: classic Z-squiggle, fully relative ─────────────────
      case MusicalSymbol.quarterRest:
        final cx = w * 0.52;
        final path = Path()
          ..moveTo(cx + w * 0.18,  h * 0.12)
          ..lineTo(cx - w * 0.12,  h * 0.34)
          ..lineTo(cx + w * 0.16,  h * 0.48)
          ..lineTo(cx - w * 0.20,  h * 0.70)
          ..quadraticBezierTo(
              cx - w * 0.30, h * 0.84,
              cx - w * 0.04, h * 0.88);
        canvas.drawPath(path, strokePaint..strokeWidth = w * 0.09);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant MusicalSymbolPainter oldDelegate) {
    return symbol != oldDelegate.symbol || color != oldDelegate.color;
  }
}