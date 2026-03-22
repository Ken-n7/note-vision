import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';

class DetectionOverlay extends StatelessWidget {
  final List<DetectedSymbol> symbols;

  const DetectionOverlay({super.key, required this.symbols});

  // color code by symbol type
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
        // scale factor from 640x640 model space to actual widget size
        final scaleX = constraints.maxWidth / 416;
        final scaleY = constraints.maxHeight / 416;

        return Stack(
          children: symbols.map((symbol) {
            final box = symbol.boundingBox;
            if (box == null) {
              return const SizedBox.shrink();
            }
            final color = _colorForSymbol(symbol);

            return Positioned(
              left: box.left * scaleX,
              top: box.top * scaleY,
              width: box.width * scaleX,
              height: box.height * scaleY,
              child: Tooltip(
                message: '${symbol.type} (${((symbol.confidence ?? 0) * 100).toStringAsFixed(1)}%)',
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
          }).toList(),
        );
      },
    );
  }
}
