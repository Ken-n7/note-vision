import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/resolution/domain/resolved_score.dart';
import 'package:note_vision/features/resolution/domain/symbol_relation_resolver.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

class BasicSymbolRelationResolver implements SymbolRelationResolver {
  const BasicSymbolRelationResolver();

  @override
  Future<ResolvedScore> resolve(
    List<DetectedSymbol> symbols,
    ScoreStructure structure,
  ) async {
    final noteSymbols = symbols.where((s) => s.musicSymbol?.isNote ?? false);
    final notes = noteSymbols
        .map((symbol) => ResolvedNote(
              symbol: symbol,
              pitch: _pitchForSymbol(symbol, structure.staveLines),
            ))
        .toList(growable: false);

    return ResolvedScore(notes: notes, symbols: symbols);
  }

  String _pitchForSymbol(DetectedSymbol symbol, List<double> staveLines) {
    if (staveLines.isEmpty) return 'unknown';
    final centerY = symbol.y + (symbol.height ?? 0) / 2;
    final min = staveLines.reduce((a, b) => a < b ? a : b);
    final max = staveLines.reduce((a, b) => a > b ? a : b);
    if (centerY < min) return 'high';
    if (centerY > max) return 'low';
    return 'mid';
  }
}
