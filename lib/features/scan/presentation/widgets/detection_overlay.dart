import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class DetectionOverlay extends StatelessWidget {
  final List<DetectedSymbol> symbols;
  final List<DetectedStaff> staffs;

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
  });

  Color _colorForSymbol(DetectedSymbol symbol) {
    final musicSymbol = symbol.musicSymbol;
    if (musicSymbol == null) return Colors.yellow;
    if (musicSymbol.isNote) return Colors.blue;
    if (musicSymbol.isRest) return Colors.green;
    if (musicSymbol.isClef) return Colors.purple;
    if (musicSymbol.isTimeSignature) return Colors.orange;
    if (musicSymbol.isAccidental) return Colors.red;
    return Colors.yellow;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale from original image pixel space → actual display space.
        // InteractiveViewer (constrained: true by default) squeezes the
        // child to the viewport size, so these may differ from imageW/H.
        final scaleX = constraints.maxWidth / imageWidth;
        final scaleY = constraints.maxHeight / imageHeight;

        return Stack(
          children: [
            // ── Staff bounding boxes + line indicators ────────────────────
            ...staffs.map(
              (staff) => _StaffOverlay(
                staff: staff,
                scaleX: scaleX,
                scaleY: scaleY,
              ),
            ),

            // ── Musical symbol bounding boxes ─────────────────────────────
            ...symbols.map((symbol) {
              final box = symbol.boundingBox;
              if (box == null) return const SizedBox.shrink();
              final color = _colorForSymbol(symbol);

              return Positioned(
                left: box.left * scaleX,
                top: box.top * scaleY,
                width: box.width * scaleX,
                height: box.height * scaleY,
                child: Tooltip(
                  message:
                      '${symbol.type} (${((symbol.confidence ?? 0) * 100).toStringAsFixed(1)}%)',
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 2),
                      color: color.withValues(alpha: 0.08),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        color: color.withValues(alpha: 0.7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Text(
                          symbol.type,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ── Staff overlay ─────────────────────────────────────────────────────────────

class _StaffOverlay extends StatelessWidget {
  static const _color = Colors.tealAccent;

  final DetectedStaff staff;
  final double scaleX;
  final double scaleY;

  const _StaffOverlay({
    required this.staff,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  Widget build(BuildContext context) {
    final labelX = staff.offsetXs.isEmpty ? 0.0 : staff.offsetXs.first;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StaffLinesPainter(staff, scaleX, scaleY, _color),
            ),
          ),

          // Staff id label
          Positioned(
            left: 4,
            top: (staff.topY + staff.offsetAt(labelX)) * scaleY + 2,
            child: Container(
              color: _color.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Text(
                staff.id,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a staff's five lines and its outer band as they run across the
/// page, following the slope and bend recorded in [DetectedStaff.offsetAt].
class _StaffLinesPainter extends CustomPainter {
  const _StaffLinesPainter(this.staff, this.scaleX, this.scaleY, this.color);

  final DetectedStaff staff;
  final double scaleX;
  final double scaleY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Path along(double levelY) {
      final path = Path();
      for (var px = 0.0; ; px += 8) {
        final x = px > size.width ? size.width : px;
        final y = (levelY + staff.offsetAt(x / scaleX)) * scaleY;
        px == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        if (x >= size.width) break;
      }
      return path;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.6);
    for (final lineY in staff.lineYs) {
      canvas.drawPath(along(lineY), line);
    }
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    canvas.drawPath(along(staff.topY), band);
    canvas.drawPath(along(staff.bottomY), band);
  }

  @override
  bool shouldRepaint(_StaffLinesPainter old) =>
      old.staff != staff || old.scaleX != scaleX || old.scaleY != scaleY;
}
