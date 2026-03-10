import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
// import 'package:note_vision/features/detection/domain/music_symbol.dart';

class DetectionOverlay extends StatelessWidget {
  final List<DetectedSymbol> symbols;

  const DetectionOverlay({super.key, required this.symbols});

  // color code by symbol type
  Color _colorForSymbol(DetectedSymbol symbol) {
    if (symbol.symbol.isNote) return Colors.blue;
    if (symbol.symbol.isRest) return Colors.green;
    if (symbol.symbol.isClef) return Colors.purple;
    if (symbol.symbol.isTimeSignature) return Colors.orange;
    if (symbol.symbol.isAccidental) return Colors.red;
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
            final color = _colorForSymbol(symbol);

            return Positioned(
              left: box.left * scaleX,
              top: box.top * scaleY,
              width: box.width * scaleX,
              height: box.height * scaleY,
              child: Tooltip(
                message: '${symbol.symbol.name} (${(symbol.confidence * 100).toStringAsFixed(1)}%)',
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 2),
                    color: color.withOpacity(0.08),
                  ),
                  child: Align( 
                    alignment: Alignment.topLeft,
                    child: Container(
                      color: color.withOpacity(0.7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      child: Text(
                        symbol.symbol.name,
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