import '../models/note.dart';
import '../models/note_value.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/musical_time.dart';
import 'accidentals.dart';
import 'score_timeline.dart';

// ---------------------------------------------------------------------------
// PlaybackEvent
// ---------------------------------------------------------------------------

/// A single synthesiser event produced from one [Note] or [Rest] symbol.
class PlaybackEvent {
  const PlaybackEvent({
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
    required this.midiNote,
    required this.baseDurationMs,
    this.isChordTone = false,
    this.baseOnsetMs = 0,
    this.baseMeasureOnsetMs = 0,
    this.baseMeasureDurationMs = 0,
  });

  final int partIndex;
  final int measureIndex;
  final int symbolIndex;

  /// MIDI key number (0–127), or -1 for rests.
  final int midiNote;

  /// Duration in ms computed at [PlaybackConverter.defaultTempo] BPM.
  /// Scale by `defaultTempo / actualTempo` to get real duration.
  final int baseDurationMs;
  final bool isChordTone;
  final int baseOnsetMs, baseMeasureOnsetMs, baseMeasureDurationMs;
  int get baseEndMs => baseOnsetMs + baseDurationMs;

  bool get isRest => midiNote < 0;

  @override
  bool operator ==(Object other) =>
      other is PlaybackEvent &&
      other.partIndex == partIndex &&
      other.measureIndex == measureIndex &&
      other.symbolIndex == symbolIndex &&
      other.midiNote == midiNote &&
      other.baseDurationMs == baseDurationMs &&
      other.isChordTone == isChordTone &&
      other.baseOnsetMs == baseOnsetMs &&
      other.baseMeasureOnsetMs == baseMeasureOnsetMs &&
      other.baseMeasureDurationMs == baseMeasureDurationMs;

  @override
  int get hashCode => Object.hash(
    partIndex,
    measureIndex,
    symbolIndex,
    midiNote,
    baseDurationMs,
    isChordTone,
    baseOnsetMs,
    baseMeasureOnsetMs,
    baseMeasureDurationMs,
  );

  @override
  String toString() =>
      'PlaybackEvent(part=$partIndex, m=$measureIndex, s=$symbolIndex, '
      'midi=$midiNote, dur=${baseDurationMs}ms'
      '${isChordTone ? ', chord: true' : ''})';
}

// ---------------------------------------------------------------------------
// PlaybackConverter
// ---------------------------------------------------------------------------

/// Pure-Dart helper that converts a [Score] model into a flat list of
/// [PlaybackEvent]s.  No platform channels — fully unit-testable.
///
/// Used internally by [PlaybackService]; exposed separately so tests can
/// exercise conversion logic without the native MIDI plugin.
class PlaybackConverter {
  const PlaybackConverter();

  /// Reference BPM used for [PlaybackEvent.baseDurationMs].
  static const int defaultTempo = 120;

  // Step → semitone offset from C (chromatic scale).
  static const Map<String, int> _stepOffset = {
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };

  // ── Public API ─────────────────────────────────────────────────────────

  /// Converts [note] to a MIDI key number (0–127), or -1 if the pitch is
  /// invalid (unknown step letter or result out of range before clamping).
  ///
  /// Formula:  (octave + 1) × 12  +  stepOffset[step]  +  (alter ?? 0)
  ///
  ///   C4  → (4+1)×12 + 0 = 60   middle C
  ///   A4  → (4+1)×12 + 9 = 69   concert A
  ///   C#4 → (4+1)×12 + 0 + 1 = 61
  ///   Bb3 → (3+1)×12 + 11 - 1 = 58
  int noteToMidi(Note note) {
    final offset = _stepOffset[note.step.toUpperCase()];
    if (offset == null) return -1;
    final midi = (note.octave + 1) * 12 + offset + (note.alter ?? 0);
    if (midi < 0 || midi > 127) return midi.clamp(0, 127);
    return midi;
  }

  /// Converts a MusicXML [divisions] count to milliseconds at
  /// [defaultTempo] BPM.
  ///
  /// Project division convention:
  ///   whole=8, half=4, quarter=2, eighth=1
  ///
  ///   At 120 BPM: 1 quarter = 500 ms
  ///   durationMs = divisions × 30 000 / defaultTempo
  ///             = divisions × 250   (at 120 BPM)
  ///
  /// Result is clamped to [50, 16 000] ms to guard against bad data.
  int durationMs(int divisions) =>
      (divisions * 30000 ~/ defaultTempo).clamp(50, 16000);

  /// Milliseconds at [defaultTempo] BPM for a length in quarter notes,
  /// clamped like [durationMs].
  int quarterMs(double quarters) =>
      (quarters * 60000 / defaultTempo).round().clamp(50, 16000);

  /// How long a note or rest written as [type] with [dots] sounds at
  /// [defaultTempo]; sixteenths and dotted eighths included. [divisions] is
  /// the stored duration, used only for an unknown type.
  int symbolMs(String type, int dots, int divisions) =>
      quarterMs(quarterLength(type, dots, divisions));

  /// Scales a [baseDurationMs] (computed at [defaultTempo]) to [actualTempo].
  int scaledDuration(int baseDurationMs, int actualTempo) =>
      (baseDurationMs * defaultTempo / actualTempo).round();

  /// Current events sorted by absolute onset. Scanned staves retain reading
  /// order; imported instrument parts share bar starts. Voices share time.
  List<PlaybackEvent> buildEvents(Score score) => buildPlan(score).events;

  PlaybackPlan buildPlan(Score score) {
    final timeline = const ScoreTimelineBuilder().build(score);
    final events = <PlaybackEvent>[];
    final accidentalStates = <int, Accidentals>{};
    for (final measure in timeline.measures) {
      final accidentals = accidentalStates.putIfAbsent(
        measure.partIndex,
        Accidentals.new,
      );
      accidentals.startMeasure(
        score.parts[measure.partIndex].measures[measure.measureIndex],
      );
      for (final timed in measure.timeline.symbols) {
        final symbol = timed.symbol;
        if (timed.symbolIndex == null || (symbol is! Note && symbol is! Rest)) {
          continue;
        }
        var midi = -1;
        if (symbol is Note) {
          midi = noteToMidi(
            Note(
              step: symbol.step,
              octave: symbol.octave,
              alter: accidentals.sounding(symbol),
              duration: symbol.duration,
              type: symbol.type,
            ),
          );
        }
        final start = baseMilliseconds(measure.onset + timed.onset);
        final end = baseMilliseconds(measure.onset + timed.end);
        events.add(
          PlaybackEvent(
            partIndex: measure.partIndex,
            measureIndex: measure.measureIndex,
            symbolIndex: timed.symbolIndex!,
            midiNote: midi,
            baseDurationMs: (end - start).clamp(1, 60000),
            baseOnsetMs: start,
            baseMeasureOnsetMs: baseMilliseconds(measure.onset),
            baseMeasureDurationMs:
                baseMilliseconds(measure.onset + measure.duration) -
                baseMilliseconds(measure.onset),
            isChordTone: timed.isChordTone,
          ),
        );
      }
    }
    events.sort((a, b) {
      final time = a.baseOnsetMs.compareTo(b.baseOnsetMs);
      if (time != 0) return time;
      final part = a.partIndex.compareTo(b.partIndex);
      if (part != 0) return part;
      final measure = a.measureIndex.compareTo(b.measureIndex);
      return measure != 0 ? measure : a.symbolIndex.compareTo(b.symbolIndex);
    });
    return PlaybackPlan(events: List.unmodifiable(events), timeline: timeline);
  }

  /// Round absolute boundaries, not each tuplet in isolation.
  static int baseMilliseconds(MusicalTime time) {
    final numerator = BigInt.from(time.numerator) * BigInt.from(500);
    final denominator = BigInt.from(time.denominator);
    return ((numerator * BigInt.two + denominator) ~/
            (denominator * BigInt.two))
        .toInt();
  }
}

class PlaybackPlan {
  const PlaybackPlan({required this.events, required this.timeline});
  final List<PlaybackEvent> events;
  final ScoreTimeline timeline;
  int get durationMs => PlaybackConverter.baseMilliseconds(timeline.duration);
}
