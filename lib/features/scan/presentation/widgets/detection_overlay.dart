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
              (staff) =>
                  _StaffOverlay(staff: staff, scaleX: scaleX, scaleY: scaleY),
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
    final scaledTop = staff.topY * scaleY;
    final scaledHeight = (staff.bottomY - staff.topY) * scaleY;

    return Positioned(
      left: 0,
      right: 0,
      top: scaledTop,
      height: scaledHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Bounding box border
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _color, width: 1.5),
                color: _color.withValues(alpha: 0.04),
              ),
            ),
          ),

          // Staff id label
          Positioned(
            left: 4,
            top: 2,
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

          // The 5 staff lines (positions are relative to scaledTop)
          ...staff.lineYs.map((lineY) {
            final relY = (lineY - staff.topY) * scaleY;
            return Positioned(
              left: 0,
              right: 0,
              top: relY,
              child: Container(height: 1, color: _color.withValues(alpha: 0.6)),
            );
          }),
        ],
      ),
    );
  }
}
