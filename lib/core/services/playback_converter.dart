import '../models/note.dart';
import '../models/rest.dart';
import '../models/score.dart';

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
  });

  final int partIndex;
  final int measureIndex;
  final int symbolIndex;

  /// MIDI key number (0–127), or -1 for rests.
  final int midiNote;

  /// Duration in ms computed at [PlaybackConverter.defaultTempo] BPM.
  /// Scale by `defaultTempo / actualTempo` to get real duration.
  final int baseDurationMs;

  bool get isRest => midiNote < 0;

  @override
  bool operator ==(Object other) =>
      other is PlaybackEvent &&
      other.partIndex == partIndex &&
      other.measureIndex == measureIndex &&
      other.symbolIndex == symbolIndex &&
      other.midiNote == midiNote &&
      other.baseDurationMs == baseDurationMs;

  @override
  int get hashCode => Object.hash(
    partIndex,
    measureIndex,
    symbolIndex,
    midiNote,
    baseDurationMs,
  );

  @override
  String toString() =>
      'PlaybackEvent(part=$partIndex, m=$measureIndex, s=$symbolIndex, '
      'midi=$midiNote, dur=${baseDurationMs}ms)';
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

  /// Scales a [baseDurationMs] (computed at [defaultTempo]) to [actualTempo].
  int scaledDuration(int baseDurationMs, int actualTempo) =>
      (baseDurationMs * defaultTempo / actualTempo).round();

  /// Flattens [score] into a sequential list of [PlaybackEvent]s.
  ///
  /// Iteration order: parts in index order, each part fully before the next.
  /// Within a part: measures in order, symbols in order.
  /// Notes with unresolvable pitch (unknown step) are skipped silently.
  List<PlaybackEvent> buildEvents(Score score) {
    final events = <PlaybackEvent>[];
    for (var pi = 0; pi < score.parts.length; pi++) {
      final part = score.parts[pi];
      for (var mi = 0; mi < part.measures.length; mi++) {
        final measure = part.measures[mi];
        for (var si = 0; si < measure.symbols.length; si++) {
          final symbol = measure.symbols[si];
          if (symbol is Note) {
            final midi = noteToMidi(symbol);
            events.add(
              PlaybackEvent(
                partIndex: pi,
                measureIndex: mi,
                symbolIndex: si,
                midiNote: midi,
                baseDurationMs: durationMs(symbol.duration),
              ),
            );
          } else if (symbol is Rest) {
            events.add(
              PlaybackEvent(
                partIndex: pi,
                measureIndex: mi,
                symbolIndex: si,
                midiNote: -1,
                baseDurationMs: durationMs(symbol.duration),
              ),
            );
          }
        }
      }
    }
    return events;
  }
}
