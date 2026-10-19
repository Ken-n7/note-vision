import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';

/// What a detected symbol is, for colouring it and for the legend.
enum SymbolKind {
  note('Note', Color(0xFF4FA3FF)),
  rest('Rest', Color(0xFF4ADE80)),
  clef('Clef', Color(0xFFC77DFF)),
  accidental('Sharp / flat', Color(0xFFFF6B6B)),
  timeSignature('Time signature', Color(0xFFFFA94D)),
  dot('Dot', Color(0xFFFFE066)),
  other('Other', Color(0xFFBDBDBD));

  const SymbolKind(this.label, this.color);

  final String label;
  final Color color;

  static SymbolKind of(DetectedSymbol symbol) {
    final s = symbol.musicSymbol;
    if (s == null) return other;
    if (s.isNote) return note;
    if (s.isRest) return rest;
    if (s.isClef) return clef;
    if (s.isAccidental) return accidental;
    if (s.isTimeSignature) return timeSignature;
    if (s == MusicSymbol.augmentationDot) return dot;
    return other;
  }
}

/// Colour of the staff lines in the overlay and the legend.
const staffOverlayColor = Colors.tealAccent;

/// Note and rest lengths as the number musicians count them by.
const _lengthLabels = {
  'whole': '1',
  'half': '2',
  'quarter': '4',
  'eighth': '8',
  'sixteenth': '16',
};

const _symbolLabels = {
  MusicSymbol.restWhole: '1',
  MusicSymbol.restHalf: '2',
  MusicSymbol.restQuarter: '4',
  MusicSymbol.rest8th: '8',
  MusicSymbol.rest16th: '16',
  MusicSymbol.clefG: 'G',
  MusicSymbol.clefF: 'F',
  MusicSymbol.accidentalSharp: '#',
  MusicSymbol.accidentalFlat: 'b',
  MusicSymbol.accidentalNatural: 'nat',
  MusicSymbol.timeSig2: '2',
  MusicSymbol.timeSig3: '3',
  MusicSymbol.timeSig4: '4',
  MusicSymbol.timeSig6: '6',
  MusicSymbol.timeSig8: '8',
  MusicSymbol.timeSigCommon: 'C',
  MusicSymbol.timeSigCutCommon: 'cut',
};

/// The short text drawn on a symbol's box: what the scan read it as. Empty
/// for symbols whose box says enough (dots).
@visibleForTesting
String overlayLabel(DetectedSymbol symbol) {
  final length = _lengthLabels[symbol.metadata?['noteType']];
  if (length != null) return length;
  return _symbolLabels[symbol.musicSymbol] ?? '';
}

/// The box the model drew around a symbol. A note's own box is shrunk to
/// its head for reading pitch; the whole box rides along in its metadata.
@visibleForTesting
Rect? overlayBox(DetectedSymbol symbol) {
  final full = symbol.metadata?[DetectedSymbol.fullBoxKey];
  if (full is List && full.length == 4) {
    final v = [for (final e in full) (e as num).toDouble()];
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }
  return symbol.boundingBox;
}

class DetectionOverlay extends StatelessWidget {
  final List<DetectedSymbol> symbols;
  final List<DetectedStaff> staffs;
  final List<DetectedBarline> barlines;

  /// Original image pixel dimensions — used to map detection coordinates
  /// (which are in original-image space) to the actual display space, which
  /// may differ because InteractiveViewer constrains the child to the
  /// viewport size.
  final int imageWidth;
  final int imageHeight;

  const DetectionOverlay({
    super.key,
    required this.symbols,
    required this.imageWidth,
    required this.imageHeight,
    this.staffs = const [],
    this.barlines = const [],
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _OverlayPainter(
        symbols,
        staffs,
        barlines,
        imageWidth,
        imageHeight,
      ),
    );
  }
}

/// Draws every staff and symbol in one pass. The overlay sits inside an
/// InteractiveViewer, so everything here grows with the pinch zoom.
class _OverlayPainter extends CustomPainter {
  const _OverlayPainter(
    this.symbols,
    this.staffs,
    this.barlines,
    this.imageWidth,
    this.imageHeight,
  );

  final List<DetectedSymbol> symbols;
  final List<DetectedStaff> staffs;
  final List<DetectedBarline> barlines;
  final int imageWidth;
  final int imageHeight;

  static const _labelSize = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from original image pixel space → actual display space.
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final sorted = [...staffs]..sort((a, b) => a.topY.compareTo(b.topY));
    for (var i = 0; i < sorted.length; i++) {
      _paintStaff(canvas, size, sorted[i], i + 1, scaleX, scaleY);
    }
    final barlinePaint = Paint()
      ..strokeWidth = 2
      ..color = staffOverlayColor;
    for (final barline in barlines) {
      final staff = staffs.where((s) => s.id == barline.staffId).firstOrNull;
      if (staff == null || staff.lineYs.isEmpty) continue;
      final offset = staff.offsetAt(barline.x);
      canvas.drawLine(
        Offset(barline.x * scaleX, (staff.lineYs.first + offset) * scaleY),
        Offset(barline.x * scaleX, (staff.lineYs.last + offset) * scaleY),
        barlinePaint,
      );
    }
    for (final symbol in symbols) {
      _paintSymbol(canvas, symbol, scaleX, scaleY);
    }
  }

  /// The five lines as they run across the page, following the slope and
  /// bend recorded in [DetectedStaff.offsetAt], and the staff's number.
  void _paintStaff(
    Canvas canvas,
    Size size,
    DetectedStaff staff,
    int number,
    double scaleX,
    double scaleY,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = staffOverlayColor.withValues(alpha: 0.7);
    for (final lineY in staff.lineYs) {
      final path = Path();
      for (var px = 0.0; ; px += 8) {
        final x = px > size.width ? size.width : px;
        final y = (lineY + staff.offsetAt(x / scaleX)) * scaleY;
        px == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        if (x >= size.width) break;
      }
      canvas.drawPath(path, paint);
    }
    // At the right end, clear of the clef and its label.
    _paintLabel(
      canvas,
      '$number',
      Offset(
        size.width - _labelSize - 3,
        (staff.topY + staff.offsetAt(size.width / scaleX)) * scaleY,
      ),
      background: staffOverlayColor,
      foreground: Colors.black,
    );
  }

  void _paintSymbol(
    Canvas canvas,
    DetectedSymbol symbol,
    double scaleX,
    double scaleY,
  ) {
    final head = symbol.boundingBox;
    final box = overlayBox(symbol);
    if (head == null || box == null) return;
    final color = SymbolKind.of(symbol).color;
    Rect scaled(Rect r) => Rect.fromLTRB(
          r.left * scaleX,
          r.top * scaleY,
          r.right * scaleX,
          r.bottom * scaleY,
        );

    final outline = scaled(box);
    canvas.drawRect(outline, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
    // Where the note's pitch is read from.
    if (box != head) {
      canvas.drawRect(scaled(head), Paint()..color = color.withValues(alpha: 0.55));
    }

    final label = overlayLabel(symbol);
    if (label.isNotEmpty) {
      _paintLabel(
        canvas,
        label,
        Offset(outline.left, outline.top - _labelSize - 2),
        background: color,
        foreground: Colors.black,
      );
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset topLeft, {
    required Color background,
    required Color foreground,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: foreground,
          fontSize: _labelSize,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = Offset(topLeft.dx, topLeft.dy < 0 ? 0 : topLeft.dy);
    canvas.drawRect(
      Rect.fromLTWH(at.dx, at.dy, painter.width + 3, painter.height + 2),
      Paint()..color = background.withValues(alpha: 0.9),
    );
    painter.paint(canvas, at + const Offset(1.5, 1));
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.symbols != symbols ||
      old.staffs != staffs ||
      old.barlines != barlines ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;
}

/// What the overlay's colours and numbers mean.
class DetectionLegend extends StatelessWidget {
  const DetectionLegend({super.key});

  static const _text = TextStyle(fontSize: 11, color: Color(0xFF8A8A8A));

  @override
  Widget build(BuildContext context) {
    Widget entry(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, color: color),
            const SizedBox(width: 5),
            Text(label, style: _text),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final kind in SymbolKind.values)
              if (kind != SymbolKind.other) entry(kind.color, kind.label),
            entry(staffOverlayColor, 'Staff / barline'),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Number on a note or rest = its length: '
          '1 whole · 2 half · 4 quarter · 8 eighth · 16 sixteenth',
          style: _text,
        ),
      ],
    );
  }
}
