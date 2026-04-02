import 'package:flutter/material.dart';
import '../../../domain/model/musical_symbol.dart';
import 'musical_symbol_painter.dart';

class PaletteItem extends StatelessWidget {
  final MusicalSymbol symbol;

  const PaletteItem({
    super.key,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<MusicalSymbol>(
      data: symbol,
      delay: const Duration(milliseconds: 180),
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.5,
          child: _buildSymbolContainer(symbol, scale: 1.5),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.32,
        child: _buildSymbolContainer(symbol),
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      child: _buildSymbolContainer(symbol),
    );
  }

  Widget _buildSymbolContainer(MusicalSymbol sym, {double scale = 1.0}) {
    return Semantics(
      label: '${sym.label} palette symbol',
      child: Container(
        width: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CustomPaint(
                  size: Size(34 * scale, 40 * scale),
                  painter: MusicalSymbolPainter(
                    symbol: sym,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sym.label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF8A8A8A),
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
