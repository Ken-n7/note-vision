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
          scale: 1.55,
          child: _buildSymbolContainer(symbol, scale: 1.55),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.32,
        child: _buildSymbolContainer(symbol),
      ),
      dragAnchorStrategy: childDragAnchorStrategy,
      child: _buildSymbolContainer(symbol),
    );
  }

  Widget _buildSymbolContainer(MusicalSymbol sym, {double scale = 1.0}) {
    return Container(
      width: 74,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: CustomPaint(
                size: Size(48 * scale, 54 * scale),
                painter: MusicalSymbolPainter(
                  symbol: sym,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
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
    );
  }
}