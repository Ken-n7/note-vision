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
        leftBarlineType: m.leftBarlineType,
        rightBarlineType: m.rightBarlineType,
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
          : _sameLength(parts),
    );
  }

  /// Every part gets as many measures as the longest, padded with empty ones:
  /// the editor pages by measure index across all parts, so a short part
  /// would hide the extra measures of the others. Staves of one scan often
  /// differ in bar count.
  static List<Part> _sameLength(List<Part> parts) {
    final longest =
        parts.map((p) => p.measures.length).reduce((a, b) => a > b ? a : b);
    return [
      for (final part in parts)
        if (part.measures.length == longest)
          part
        else
          Part(
            id: part.id,
            name: part.name,
            measures: [
              ...part.measures,
              for (var n = part.measures.length + 1; n <= longest; n++)
                Measure(number: n, symbols: const []),
            ],
          ),
    ];
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
