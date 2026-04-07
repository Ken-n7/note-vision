import 'package:flutter/material.dart';
import 'package:note_vision/core/theme/app_theme.dart';

const Color _paletteSymbolColor = Color(0xFFE6E6E6);
const Color _paletteSymbolSelected = Color(0xFFD4A96A);

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
  const SymbolPalette({
    super.key,
    this.selectedType,
    this.onTypeTap,
  });

  final PaletteSymbolType? selectedType;
  final ValueChanged<PaletteSymbolType>? onTypeTap;

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
    return Container(
      key: const ValueKey('symbol-palette'),
      height: 88,
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: _items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PaletteDraggableItem(
                    item: item,
                    isSelected: selectedType == item.type,
                    onTap: onTypeTap != null ? () => onTypeTap!(item.type) : null,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _PaletteDraggableItem extends StatelessWidget {
  const _PaletteDraggableItem({
    required this.item,
    required this.isSelected,
    this.onTap,
  });

  final _PaletteItemData item;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final core = _PaletteVisual(item: item, isSelected: isSelected);
    final dragFeedback = CustomPaint(
      size: const Size(34, 40),
      painter: _PaletteSymbolPainter(
        type: item.type,
        color: _paletteSymbolSelected,
      ),
    );
    return LongPressDraggable<PaletteDragData>(
      data: PaletteDragData(type: item.type),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.7, child: dragFeedback),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: core),
      child: GestureDetector(onTap: onTap, child: core),
    );
  }
}

class _PaletteVisual extends StatelessWidget {
  const _PaletteVisual({required this.item, required this.isSelected});

  final _PaletteItemData item;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.15)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.accent : AppColors.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(28, 34),
            painter: _PaletteSymbolPainter(
              type: item.type,
              color: isSelected ? _paletteSymbolSelected : _paletteSymbolColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 9,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
  const _PaletteSymbolPainter({required this.type, required this.color});

  final PaletteSymbolType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
      canvas.drawOval(headRect, Paint()..color = color..style = PaintingStyle.fill);
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
    canvas.drawRect(barRect, Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawLine(Offset(size.width * 0.2, lineY), Offset(size.width * 0.8, lineY), paint);
  }

  void _drawHalfRest(Canvas canvas, Paint paint, Size size) {
    final lineY = size.height * 0.52;
    final barRect = Rect.fromLTWH(size.width * 0.28, lineY - 6, size.width * 0.44, 6);
    canvas.drawRect(barRect, Paint()..color = color..style = PaintingStyle.fill);
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
  bool shouldRepaint(covariant _PaletteSymbolPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}

class _PaletteItemData {
  const _PaletteItemData({required this.type, required this.label});

  final PaletteSymbolType type;
  final String label;
}
