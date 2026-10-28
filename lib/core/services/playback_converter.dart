import 'dart:math' as math;

import '../models/note.dart';
import '../models/note_value.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/musical_time.dart';
import 'accidentals.dart';
import 'score_timeline.dart';
import 'spanners.dart';

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
    this.velocity = PlaybackConverter.defaultVelocity,
  });

  /// MIDI velocity (loudness), from dynamics and hairpins.
  final int velocity;

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
      other.baseMeasureDurationMs == baseMeasureDurationMs &&
      other.velocity == velocity;

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
    velocity,
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

  /// Velocity without a dynamic: mf, as in MuseScore Studio.
  static const int defaultVelocity = 80;

  /// MuseScore Studio's velocity for each sustained dynamic.
  static const _levels = {
    'pppppp': 1,
    'ppppp': 5,
    'pppp': 10,
    'ppp': 16,
    'pp': 33,
    'p': 49,
    'mp': 64,
    'mf': 80,
    'f': 96,
    'ff': 112,
    'fff': 126,
    'ffff': 127,
    'fffff': 127,
    'ffffff': 127,
  };

  /// Dynamics that stress one note: its velocity, then the level after it
  /// (null keeps the level before).
  static const _accents = <String, (int, int?)>{
    'sf': (112, null),
    'sfz': (112, null),
    'sffz': (126, null),
    'fz': (112, null),
    'rf': (112, null),
    'rfz': (112, null),
    'fp': (96, 49),
    'sfp': (112, 49),
    'sfpp': (112, 33),
    'pf': (49, 96),
    'sfzp': (112, 49),
  };

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
    _mergeTies(score, events);
    _applyDynamics(score, events);
    _applyMarks(score, events);
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

  /// Velocities from dynamics and hairpins, per staff, as MuseScore Studio
  /// plays them: a dynamic holds until the next; sfz and the like stress
  /// one note; a hairpin glides over time to the next dynamic in its
  /// direction, or one level further when there is none.
  void _applyDynamics(Score score, List<PlaybackEvent> events) {
    final hairpins = [
      for (final h in SpannerIndex(score).live)
        if (h.$1.kind.isHairpin) h,
    ];
    final steps = _levels.values.toSet().toList()..sort();
    for (var p = 0; p < score.parts.length; p++) {
      final order = [
        for (final (i, e) in events.indexed)
          if (e.partIndex == p) i,
      ]..sort((a, b) => events[a].baseOnsetMs - events[b].baseOnsetMs);
      if (order.isEmpty) continue;
      var level = defaultVelocity;
      int? stressAt;
      int? stress;
      final velocity = <int, int>{};
      final sustained = <(int, int)>[]; // (onset, level)
      for (final i in order) {
        final e = events[i];
        final mark = switch (score.parts[p].measures[e.measureIndex].symbols[e
            .symbolIndex]) {
          Note(:final dynamicMark) || Rest(:final dynamicMark) => dynamicMark,
          _ => null,
        };
        if (_levels[mark] case final next?) {
          level = next;
          sustained.add((e.baseOnsetMs, level));
        } else if (_accents[mark] case (final hit, final after)) {
          (stressAt, stress) = (e.baseOnsetMs, hit);
          if (after != null) {
            level = after;
            sustained.add((e.baseOnsetMs, level));
          }
        }
        velocity[i] = e.baseOnsetMs == stressAt ? stress! : level;
      }
      final at = {
        for (final i in order)
          (
            part: p,
            measure: events[i].measureIndex,
            symbol: events[i].symbolIndex,
          ): i,
      };
      for (final (spanner, from, to) in hairpins) {
        final (a, b) = (at[from], at[to]);
        if (from.part != p || a == null || b == null) continue;
        final start = events[a].baseOnsetMs;
        final end = events[b].baseEndMs;
        final startLevel = velocity[a]!;
        final louder = spanner.kind == SpannerKind.crescendo;
        final next = sustained
            .where((s) => s.$1 >= end - 1)
            .map((s) => s.$2)
            .firstOrNull;
        final target =
            next != null && (louder ? next > startLevel : next < startLevel)
            ? next
            : louder
            ? steps.firstWhere((v) => v > startLevel, orElse: () => 127)
            : steps.lastWhere((v) => v < startLevel, orElse: () => 1);
        for (final i in order) {
          final t = events[i].baseOnsetMs;
          if (t < start || t >= end || end == start) continue;
          velocity[i] =
              (startLevel + (target - startLevel) * (t - start) / (end - start))
                  .toInt(); // MuseScore truncates
        }
      }
      for (final i in order) {
        if (velocity[i] != events[i].velocity) {
          events[i] = _with(events[i], velocity: velocity[i]);
        }
      }
    }
  }

  /// Articulations and ornaments as MuseScore Studio plays them: staccato
  /// sounds half the note, staccatissimo 33%, marcato two thirds; accents
  /// and marcatos one dynamic level louder; trills,
  /// mordents and turns play 32nd notes (an eighth of a beat) with the
  /// neighbouring notes of the key.
  void _applyMarks(Score score, List<PlaybackEvent> events) {
    const thirtySecond = 62.5; // ms at the base tempo
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e.isRest) continue;
      final symbol = score
          .parts[e.partIndex]
          .measures[e.measureIndex]
          .symbols[e.symbolIndex];
      if (symbol is! Note || symbol.marks.isEmpty) continue;
      final marks = symbol.marks;
      final gate = marks.contains(Articulation.staccatissimo)
          ? 0.33
          : marks.contains(Articulation.staccato)
          ? 1 / 2
          : marks.contains(Articulation.marcato)
          ? 2 / 3
          : 1.0;
      if (gate < 1) {
        events[i] = _with(e, durationMs: (e.baseDurationMs * gate).round());
      }
      // An accent or marcato plays one dynamic level louder.
      if (marks.contains(Articulation.accent) ||
          marks.contains(Articulation.marcato)) {
        final louder = _levels.values.where((v) => v > e.velocity);
        events[i] = _with(
          events[i],
          velocity: louder.isEmpty ? 127 : louder.reduce(math.min),
        );
      }
      // Steps from the written note, one per 32nd; the last holds on.
      final List<int>? pattern = marks.contains(Articulation.trill)
          ? [
              for (var k = 0; k < e.baseDurationMs ~/ thirtySecond; k++)
                k.isEven ? 0 : 1,
            ]
          : marks.contains(Articulation.mordent)
          ? [0, -1, 0]
          : marks.contains(Articulation.invertedMordent)
          ? [0, 1, 0]
          : marks.contains(Articulation.turn)
          ? [1, 0, -1, 0]
          : null;
      if (pattern == null || pattern.length < 2) continue;
      final key = ScoreTimelineBuilder.activeKey(
        score,
        e.partIndex,
        e.measureIndex,
      );
      int neighbour(int steps) {
        if (steps == 0) return e.midiNote;
        const names = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
        final d = symbol.octave * 7 + names.indexOf(symbol.step) + steps;
        final step = names[d % 7];
        return noteToMidi(
          Note(
            step: step,
            octave: d ~/ 7,
            alter: Accidentals.keyAlter(key, step),
            duration: 1,
            type: 'quarter',
          ),
        );
      }

      final notes = [
        for (final (k, steps) in pattern.indexed)
          _with(
            e,
            midiNote: neighbour(steps),
            onsetMs: e.baseOnsetMs + (k * thirtySecond).round(),
            durationMs: k == pattern.length - 1
                ? e.baseEndMs - e.baseOnsetMs - (k * thirtySecond).round()
                : ((k + 1) * thirtySecond).round() - (k * thirtySecond).round(),
          ),
      ];
      events.replaceRange(i, i + 1, notes);
    }
  }

  /// A tied note sounds once, held to the end of the last note it is tied
  /// to; the notes it continues into are silent.
  static void _mergeTies(Score score, List<PlaybackEvent> events) {
    final ties = [
      for (final t in SpannerIndex(score).live)
        if (t.$1.kind == SpannerKind.tie) t,
    ];
    if (ties.isEmpty) return;
    final at = {
      for (final (i, e) in events.indexed)
        (part: e.partIndex, measure: e.measureIndex, symbol: e.symbolIndex): i,
    };
    final head = <int, int>{};
    ties.sort(
      (a, b) => (events[at[a.$2] ?? 0].baseOnsetMs).compareTo(
        events[at[b.$2] ?? 0].baseOnsetMs,
      ),
    );
    for (final (_, from, to) in ties) {
      final (a, b) = (at[from], at[to]);
      if (a == null || b == null || events[a].midiNote != events[b].midiNote) {
        continue;
      }
      final h = head[a] ?? a;
      events[h] = _with(
        events[h],
        durationMs: events[b].baseEndMs - events[h].baseOnsetMs,
      );
      events[b] = _with(events[b], midiNote: -1);
      head[b] = h;
    }
  }

  static PlaybackEvent _with(
    PlaybackEvent e, {
    int? midiNote,
    int? durationMs,
    int? onsetMs,
    int? velocity,
  }) => PlaybackEvent(
    partIndex: e.partIndex,
    measureIndex: e.measureIndex,
    symbolIndex: e.symbolIndex,
    midiNote: midiNote ?? e.midiNote,
    baseDurationMs: durationMs ?? e.baseDurationMs,
    isChordTone: e.isChordTone,
    baseOnsetMs: onsetMs ?? e.baseOnsetMs,
    velocity: velocity ?? e.velocity,
    baseMeasureOnsetMs: e.baseMeasureOnsetMs,
    baseMeasureDurationMs: e.baseMeasureDurationMs,
  );

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
