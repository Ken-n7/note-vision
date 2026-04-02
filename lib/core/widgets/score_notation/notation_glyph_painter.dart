import 'package:flutter/material.dart';

import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score_symbol.dart';
import 'staff_pitch_mapper.dart';

class NotationGlyphPainter {
  const NotationGlyphPainter._();

  static double symbolCenterY({
    required ScoreSymbol symbol,
    required double staffTop,
    required double staffBottom,
    required double staffLineSpacing,
  }) {
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

  static void drawSelectionHighlight(Canvas canvas, Offset center, {double radius = 14}) {
    final paint = Paint()
      ..color = const Color(0xFFD4A96A).withValues(alpha: 0.26)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
  }

  static void drawNote(
    Canvas canvas,
    Note note, {
    required double x,
    required double y,
    required double middleLineY,
    required double staffLineSpacing,
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
      staffLineSpacing: staffLineSpacing,
    );
  }

  static void drawRest(
    Canvas canvas,
    Rest rest, {
    required double x,
    required double staffTop,
    required double staffLineSpacing,
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

  static void _drawStemAndFlag(
    Canvas canvas, {
    required double x,
    required double y,
    required bool stemUp,
    required bool drawFlag,
    required double staffLineSpacing,
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
}
