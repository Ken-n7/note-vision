import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'mapping_types.dart';

class ScoreBuilder {
  const ScoreBuilder();

  /// Builds a [Part] from a list of [SemanticMeasure]s.
  ///
  /// Carries the last-seen clef, time signature, and key signature forward to
  /// any subsequent measure that does not explicitly declare one.
  Part buildPart(
    List<SemanticMeasure> measures, {
    required String partId,
    required String partName,
  }) {
    if (measures.isEmpty) {
      return Part(
        id: partId,
        name: partName,
        measures: const [Measure(number: 1, symbols: [])],
      );
    }

    Clef? lastClef;
    TimeSignature? lastTime;
    KeySignature? lastKey;
    final built = <Measure>[];

    for (final m in measures) {
      if (m.clef != null) lastClef = m.clef;
      if (m.timeSignature != null) lastTime = m.timeSignature;
      if (m.keySignature != null) lastKey = m.keySignature;

      built.add(Measure(
        number: m.number,
        clef: m.clef ?? lastClef,
        timeSignature: m.timeSignature ?? lastTime,
        keySignature: m.keySignature ?? lastKey,
        symbols: m.symbols,
      ));
    }

    return Part(id: partId, name: partName, measures: List.unmodifiable(built));
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
