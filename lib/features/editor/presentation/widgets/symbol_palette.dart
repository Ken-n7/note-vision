import 'package:flutter/material.dart';

const Color _paletteBackground = Color(0xFF1A1A1A);
const Color _paletteTopBorder = Color(0xFF2C2C2C);
const Color _paletteLabelColor = Color(0xFF8A8A8A);
const Color _paletteSymbolColor = Color(0xFFE6E6E6);

enum PaletteSymbolType {
  wholeNote,
  halfNote,
  quarterNote,
  eighthNote,
  wholeRest,
  halfRest,
  quarterRest,
}

class PaletteDragData {
  const PaletteDragData({required this.type});

  final PaletteSymbolType type;
}

class SymbolPalette extends StatelessWidget {
  const SymbolPalette({super.key, this.isCompact = false});

  final bool isCompact;

  static const List<_PaletteItemData> _items = [
    _PaletteItemData(type: PaletteSymbolType.wholeNote, label: 'Whole'),
    _PaletteItemData(type: PaletteSymbolType.halfNote, label: 'Half'),
    _PaletteItemData(type: PaletteSymbolType.quarterNote, label: 'Quarter'),
    _PaletteItemData(type: PaletteSymbolType.eighthNote, label: 'Eighth'),
    _PaletteItemData(type: PaletteSymbolType.wholeRest, label: 'W Rest'),
    _PaletteItemData(type: PaletteSymbolType.halfRest, label: 'H Rest'),
    _PaletteItemData(type: PaletteSymbolType.quarterRest, label: 'Q Rest'),
  ];

  @override
  Widget build(BuildContext context) {
    final paletteHeight = isCompact ? 132.0 : 100.0;
    return Container(
      key: const ValueKey('symbol-palette'),
      height: paletteHeight,
      decoration: const BoxDecoration(
        color: _paletteBackground,
        border: Border(
          top: BorderSide(color: _paletteTopBorder, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactLayout = isCompact || constraints.maxWidth < 480;
          if (!compactLayout) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: _items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _PaletteDraggableItem(item: item),
                      ),
                    )
                    .toList(growable: false),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _items
                  .map(
                    (item) => _PaletteDraggableItem(
                      item: item,
                      compact: true,
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        },
      ),
    );
  }
}

class _PaletteDraggableItem extends StatelessWidget {
  const _PaletteDraggableItem({required this.item, this.compact = false});

  final _PaletteItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final core = _PaletteVisual(item: item, compact: compact);
    return LongPressDraggable<PaletteDragData>(
      data: PaletteDragData(type: item.type),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.5,
          child: core,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: core),
      child: core,
    );
  }
}

class _PaletteVisual extends StatelessWidget {
  const _PaletteVisual({required this.item, this.compact = false});

  final _PaletteItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 56 : 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(compact ? 28 : 32, compact ? 34 : 42),
            painter: _PaletteSymbolPainter(type: item.type),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            item.label,
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              color: _paletteLabelColor,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PaletteSymbolPainter extends CustomPainter {
  const _PaletteSymbolPainter({required this.type});

  final PaletteSymbolType type;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paletteSymbolColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    switch (type) {
      case PaletteSymbolType.wholeNote:
        _drawNote(canvas, paint, size, filled: false, withStem: false, withFlag: false);
      case PaletteSymbolType.halfNote:
        _drawNote(canvas, paint, size, filled: false, withStem: true, withFlag: false);
      case PaletteSymbolType.quarterNote:
        _drawNote(canvas, paint, size, filled: true, withStem: true, withFlag: false);
      case PaletteSymbolType.eighthNote:
        _drawNote(canvas, paint, size, filled: true, withStem: true, withFlag: true);
      case PaletteSymbolType.wholeRest:
        _drawWholeRest(canvas, paint, size);
      case PaletteSymbolType.halfRest:
        _drawHalfRest(canvas, paint, size);
      case PaletteSymbolType.quarterRest:
        _drawQuarterRest(canvas, paint, size);
    }
  }

  void _drawNote(
    Canvas canvas,
    Paint paint,
    Size size, {
    required bool filled,
    required bool withStem,
    required bool withFlag,
  }) {
    final headRect = Rect.fromCenter(
      center: Offset(size.width * 0.44, size.height * 0.68),
      width: 14,
      height: 10,
    );

    if (filled) {
      canvas.drawOval(
        headRect,
        Paint()
          ..color = _paletteSymbolColor
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawOval(headRect, paint);
    }

    if (!withStem) return;

    final stemStart = Offset(headRect.right - 1, headRect.center.dy);
    final stemEnd = Offset(stemStart.dx, size.height * 0.2);
    canvas.drawLine(stemStart, stemEnd, paint);

    if (withFlag) {
      final path = Path()
        ..moveTo(stemEnd.dx, stemEnd.dy)
        ..quadraticBezierTo(stemEnd.dx + 8, stemEnd.dy + 3, stemEnd.dx + 5, stemEnd.dy + 11);
      canvas.drawPath(path, paint);
    }
  }

  void _drawWholeRest(Canvas canvas, Paint paint, Size size) {
    final lineY = size.height * 0.45;
    final barRect = Rect.fromLTWH(size.width * 0.28, lineY, size.width * 0.44, 6);
    canvas.drawRect(
      barRect,
      Paint()
        ..color = _paletteSymbolColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(Offset(size.width * 0.2, lineY), Offset(size.width * 0.8, lineY), paint);
  }

  void _drawHalfRest(Canvas canvas, Paint paint, Size size) {
    final lineY = size.height * 0.52;
    final barRect = Rect.fromLTWH(size.width * 0.28, lineY - 6, size.width * 0.44, 6);
    canvas.drawRect(
      barRect,
      Paint()
        ..color = _paletteSymbolColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(Offset(size.width * 0.2, lineY), Offset(size.width * 0.8, lineY), paint);
  }

  void _drawQuarterRest(Canvas canvas, Paint paint, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.55, size.height * 0.18)
      ..lineTo(size.width * 0.38, size.height * 0.38)
      ..lineTo(size.width * 0.54, size.height * 0.48)
      ..lineTo(size.width * 0.4, size.height * 0.7)
      ..lineTo(size.width * 0.56, size.height * 0.82);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PaletteSymbolPainter oldDelegate) => oldDelegate.type != type;
}

class _PaletteItemData {
  const _PaletteItemData({required this.type, required this.label});

  final PaletteSymbolType type;
  final String label;
}
