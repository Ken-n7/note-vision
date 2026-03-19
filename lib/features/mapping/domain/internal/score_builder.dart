import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'mapping_types.dart';

class ScoreBuilder {
  const ScoreBuilder();

  Score build(List<SemanticMeasure> measures) {
    return Score(
      id: 'mapped-score',
      title: '',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Detected Part',
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
        ),
      ],
    );
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