import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';

import 'resolved_score.dart';

abstract class SymbolRelationResolver {
  Future<ResolvedScore> resolve(
    List<DetectedSymbol> symbols,
    ScoreStructure structure,
  );
}
