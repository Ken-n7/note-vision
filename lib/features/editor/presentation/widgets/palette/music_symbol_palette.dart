import 'package:flutter/material.dart';
import '../../../domain/model/musical_symbol.dart';
import 'palette_item.dart';

class MusicSymbolPalette extends StatelessWidget {
  const MusicSymbolPalette({super.key});

  @override
  Widget build(BuildContext context) {
    const symbols = [
      MusicalSymbol.wholeNote,
      MusicalSymbol.halfNote,
      MusicalSymbol.quarterNote,
      MusicalSymbol.eighthNote,
      MusicalSymbol.wholeRest,
      MusicalSymbol.halfRest,
      MusicalSymbol.quarterRest,
    ];

    return Container(
      height: 122,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: Color(0xFF2C2C2C), width: 1.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: symbols
              .map((symbol) => PaletteItem(symbol: symbol))
              .toList(),
        ),
      ),
    );
  }
}