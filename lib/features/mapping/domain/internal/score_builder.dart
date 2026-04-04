import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'mapping_types.dart';

class ScoreBuilder {
  const ScoreBuilder();

  /// Builds a [Part] from a list of [SemanticMeasure]s.
  Part buildPart(
    List<SemanticMeasure> measures, {
    required String partId,
    required String partName,
  }) {
    return Part(
      id: partId,
      name: partName,
      measures: measures.isEmpty
          ? const [Measure(number: 1, symbols: [])]
          : measures
              .map((m) => Measure(
                    number: m.number,
                    clef: m.clef,
                    timeSignature: m.timeSignature,
                    keySignature: m.keySignature,
                    symbols: m.symbols,
                  ))
              .toList(growable: false),
    );
  }

  /// Builds a [Score] from a list of already-built [Part]s.
  Score buildFromParts(List<Part> parts) {
    return Score(
      id: 'mapped-score',
      title: '',
      composer: '',
      parts: parts.isEmpty
          ? const [Part(id: 'P1', name: 'Detected Part', measures: [Measure(number: 1, symbols: [])])]
          : parts,
    );
  }

  /// Convenience: single-pass build for a single part (used by legacy callers).
  Score build(List<SemanticMeasure> measures) {
    return buildFromParts([
      buildPart(measures, partId: 'P1', partName: 'Detected Part'),
    ]);
  }

  Score buildEmpty() => const Score(
        id: 'mapped-score',
        title: '',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Detected Part',
            measures: [Measure(number: 1, symbols: [])],
          ),
        ],
      );
}
