import '../models/key_signature.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/part.dart';
import '../models/score.dart';
import 'accidentals.dart';

/// A diatonic distance and its size in semitones: a major second is (1, 2).
typedef Interval = ({int steps, int semitones});

/// MuseScore Studio's interval list; the index is its `transposeInterval`.
const transposeIntervals = <(String, Interval)>[
  ('Perfect unison', (steps: 0, semitones: 0)),
  ('Augmented unison', (steps: 0, semitones: 1)),
  ('Diminished second', (steps: 1, semitones: 0)),
  ('Minor second', (steps: 1, semitones: 1)),
  ('Major second', (steps: 1, semitones: 2)),
  ('Augmented second', (steps: 1, semitones: 3)),
  ('Diminished third', (steps: 2, semitones: 2)),
  ('Minor third', (steps: 2, semitones: 3)),
  ('Major third', (steps: 2, semitones: 4)),
  ('Augmented third', (steps: 2, semitones: 5)),
  ('Diminished fourth', (steps: 3, semitones: 4)),
  ('Perfect fourth', (steps: 3, semitones: 5)),
  ('Augmented fourth', (steps: 3, semitones: 6)),
  ('Diminished fifth', (steps: 4, semitones: 6)),
  ('Perfect fifth', (steps: 4, semitones: 7)),
  ('Augmented fifth', (steps: 4, semitones: 8)),
  ('Diminished sixth', (steps: 5, semitones: 7)),
  ('Minor sixth', (steps: 5, semitones: 8)),
  ('Major sixth', (steps: 5, semitones: 9)),
  ('Augmented sixth', (steps: 5, semitones: 10)),
  ('Diminished seventh', (steps: 6, semitones: 9)),
  ('Minor seventh', (steps: 6, semitones: 10)),
  ('Major seventh', (steps: 6, semitones: 11)),
  ('Augmented seventh', (steps: 6, semitones: 12)),
  ('Diminished octave', (steps: 7, semitones: 11)),
  ('Perfect octave', (steps: 7, semitones: 12)),
];

enum TransposeMode { toKey, byInterval, diatonic }

enum TransposeDirection { up, down, closest }

/// The choices in MuseScore Studio's Transpose dialog.
class TransposeOptions {
  const TransposeOptions({
    required this.mode,
    this.direction = TransposeDirection.up,
    this.targetKey = 0,
    this.interval = 0,
    this.keySignatures = true,
    this.doubleAccidentals = false,
  });

  final TransposeMode mode;
  final TransposeDirection direction;

  /// [TransposeMode.toKey]: the new key, in fifths.
  final int targetKey;

  /// [TransposeMode.byInterval]: an index into [transposeIntervals].
  /// [TransposeMode.diatonic]: staff steps (1 is a second).
  final int interval;

  /// [TransposeMode.byInterval]: move key signatures too.
  final bool keySignatures;

  /// Allow double sharps and flats; otherwise such notes are respelled.
  final bool doubleAccidentals;
}

/// Transposes every note and key signature, keeping rhythm and evidence.
/// Pitches are moved as heard (key and earlier accidentals in the bar
/// included), then accidentals are written again for the new key.
class Transposer {
  const Transposer();

  static const _naturalSemitones = [0, 2, 4, 5, 7, 9, 11];
  static const _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  Score transpose(Score score, TransposeOptions options) {
    final firstKey =
        score.parts.firstOrNull?.measures.firstOrNull?.keySignature?.fifths ??
        0;
    var interval = (steps: 0, semitones: 0);
    var keyShift = 0;
    switch (options.mode) {
      case TransposeMode.toKey:
        keyShift = options.targetKey - firstKey;
        interval = _intervalForFifths(keyShift, options.direction);
      case TransposeMode.byInterval:
        interval = transposeIntervals[options.interval].$2;
        if (options.direction == TransposeDirection.down) {
          interval = (steps: -interval.steps, semitones: -interval.semitones);
        }
        if (options.keySignatures) {
          keyShift = 7 * interval.semitones - 12 * interval.steps;
        }
      case TransposeMode.diatonic:
        final steps = options.direction == TransposeDirection.down
            ? -options.interval
            : options.interval;
        interval = (steps: steps, semitones: 0);
    }
    return score.copyWith(
      parts: [
        for (final part in score.parts)
          _part(part, options, interval, keyShift),
      ],
    );
  }

  Part _part(
    Part part,
    TransposeOptions options,
    Interval interval,
    int keyShift,
  ) {
    final reading = Accidentals();
    final writing = Accidentals();
    final diatonic = options.mode == TransposeMode.diatonic;
    final limit = options.doubleAccidentals ? 2 : 1;
    KeySignature? oldKey;
    KeySignature? newKey;
    final measures = <Measure>[];
    for (final (index, measure) in part.measures.indexed) {
      reading.startMeasure(measure);
      oldKey = measure.keySignature ?? oldKey;
      final key = keyShift == 0
          ? measure.keySignature
          : measure.keySignature != null || index == 0
          ? KeySignature(
              fifths: _enharmonicKey(
                (measure.keySignature?.fifths ?? 0) + keyShift,
              ),
            )
          : null;
      newKey = key ?? newKey;
      final next = measure.withContent(
        keySignature: key,
        symbols: measure.symbols,
      );
      writing.startMeasure(next);
      measures.add(
        next.withContent(
          keySignature: key,
          symbols: [
            for (final symbol in measure.symbols)
              if (symbol is Note)
                () {
                  final sounding = reading.sounding(symbol);
                  final from = symbol.octave * 7 + _steps.indexOf(symbol.step);
                  final to = from + interval.steps;
                  final semitone = diatonic
                      ? _natural(to) +
                            Accidentals.keyAlter(newKey, _steps[to % 7]) +
                            sounding -
                            Accidentals.keyAlter(oldKey, symbol.step)
                      : _natural(from) + sounding + interval.semitones;
                  final (step, octave, alter) = _spell(to, semitone, limit);
                  final placed = symbol.withPitch(step, octave, null);
                  return placed.withPitch(
                    step,
                    octave,
                    writing.written(placed, alter),
                  );
                }()
              else
                symbol,
          ],
        ),
      );
    }
    return Part(id: part.id, name: part.name, measures: measures);
  }

  /// Past seven sharps or flats, the enharmonic key twelve fifths away.
  /// Notes keep the interval's spelling, as in MuseScore Studio.
  static int _enharmonicKey(int fifths) => fifths > 7
      ? fifths - 12
      : fifths < -7
      ? fifths + 12
      : fifths;

  /// Semitones above C0 of the unaltered note [diatonic] steps above C0.
  static int _natural(int diatonic) =>
      12 * (diatonic ~/ 7) + _naturalSemitones[diatonic % 7];

  /// [semitone] written on staff step [diatonic], or a neighbouring step when
  /// that would need more than [limit] sharps or flats.
  static (String, int, int) _spell(int diatonic, int semitone, int limit) {
    var best = diatonic;
    for (final candidate in [diatonic, diatonic - 1, diatonic + 1]) {
      final alter = semitone - _natural(candidate);
      if (alter.abs() <= limit) {
        best = candidate;
        break;
      }
    }
    return (_steps[best % 7], best ~/ 7, semitone - _natural(best));
  }

  /// The interval between two keys [fifths] apart, in [direction].
  static Interval _intervalForFifths(int fifths, TransposeDirection direction) {
    final steps = (4 * fifths) % 7;
    // The octave-equivalent size closest to the step's natural size.
    var semitones = (7 * fifths) % 12;
    if (steps == 6 && semitones < 6) semitones += 12;
    if (steps == 0 && semitones > 6) semitones -= 12;
    final up = (steps: steps, semitones: semitones);
    final down = steps == 0 && semitones <= 0
        ? up
        : (steps: steps - 7, semitones: semitones - 12);
    return switch (direction) {
      TransposeDirection.up =>
        semitones < 0 ? (steps: steps + 7, semitones: semitones + 12) : up,
      TransposeDirection.down => down,
      TransposeDirection.closest =>
        up.semitones.abs() <= down.semitones.abs() ? up : down,
    };
  }
}
