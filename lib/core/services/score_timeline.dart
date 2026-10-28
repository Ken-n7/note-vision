import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/key_signature.dart';
import '../models/barline_type.dart';
import '../models/measure.dart';
import '../models/navigation_mark.dart';
import '../models/musical_time.dart';
import '../models/musicxml_source.dart';
import '../models/note.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/score_symbol.dart';
import '../models/time_signature.dart';

typedef VoiceLane = (String voice, int staff);

class ScoreTimelineException implements Exception {
  const ScoreTimelineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A position in the current score, in exact quarter notes within a measure.
/// Unrepresented source notes retain time but have no editable symbol index.
class TimedScoreSymbol {
  const TimedScoreSymbol({
    required this.symbolIndex,
    required this.symbol,
    required this.onset,
    required this.duration,
    required this.lane,
    required this.isChordTone,
  });
  final int? symbolIndex;
  final ScoreSymbol? symbol;
  final MusicalTime onset, duration;
  final VoiceLane lane;
  final bool isChordTone;
  MusicalTime get end => onset + duration;
}

class MeasureTimeline {
  MeasureTimeline(Iterable<TimedScoreSymbol> symbols)
    : symbols = List.unmodifiable(symbols);
  final List<TimedScoreSymbol> symbols;
  MusicalTime get duration => symbols.fold(
    MusicalTime.zero,
    (end, event) => event.end.compareTo(end) > 0 ? event.end : end,
  );
  MusicalTime laneDuration(VoiceLane lane) => symbols
      .where((e) => e.lane == lane)
      .fold(
        MusicalTime.zero,
        (end, e) => e.end.compareTo(end) > 0 ? e.end : end,
      );
}

class ScoreTimelineMeasure {
  const ScoreTimelineMeasure({
    required this.partIndex,
    required this.measureIndex,
    required this.onset,
    required this.duration,
    required this.timeline,
  });
  final int partIndex, measureIndex;
  final MusicalTime onset, duration;
  final MeasureTimeline timeline;
}

class ScoreTimeline {
  ScoreTimeline({
    required Iterable<ScoreTimelineMeasure> measures,
    required this.duration,
  }) : measures = List.unmodifiable(measures);
  final List<ScoreTimelineMeasure> measures;
  final MusicalTime duration;
}

/// Builds live time from current symbols, preserving source ratios and gaps
/// only while bindings still identify the same source sequence. Source time is
/// never treated as current after an unsupported structural change.
class ScoreTimelineBuilder {
  const ScoreTimelineBuilder();
  static final _sourceContexts = Expando<_SourceTimingContext>();

  static VoiceLane lane(ScoreSymbol symbol) => switch (symbol) {
    Note(:final voice, :final staff) ||
    Rest(:final voice, :final staff) => ('${voice ?? 1}', staff ?? 1),
    _ => ('1', 1),
  };

  /// A note or rest's length as it sounds: its written value, shortened
  /// exactly by its tuplet.
  static MusicalTime writtenDuration(ScoreSymbol symbol) {
    final tuplet = switch (symbol) {
      Note(:final tuplet) || Rest(:final tuplet) => tuplet,
      _ => null,
    };
    final value = _writtenValue(symbol);
    return tuplet == null
        ? value
        : value * MusicalTime(tuplet.normal, tuplet.actual);
  }

  static MusicalTime _writtenValue(ScoreSymbol symbol) {
    final (type, dots, stored) = switch (symbol) {
      Note(:final type, :final dots, :final duration) ||
      Rest(
        :final type,
        :final dots,
        :final duration,
      ) => (type.trim().toLowerCase(), dots, duration),
      _ => ('', 0, 0),
    };
    if (dots < 0 || dots > 16) {
      throw const ScoreTimelineException(
        'This duration is outside the supported range.',
      );
    }
    final base = switch (type) {
      'breve' => MusicalTime(8),
      'whole' => MusicalTime(4),
      'half' => MusicalTime(2),
      'quarter' => MusicalTime.one,
      'eighth' => MusicalTime(1, 2),
      'sixteenth' || '16th' => MusicalTime(1, 4),
      '32nd' => MusicalTime(1, 8),
      _ => MusicalTime(stored, 2),
    };
    if (base.isNegative) {
      throw const ScoreTimelineException('A duration cannot be negative.');
    }
    if (!{
      'breve',
      'whole',
      'half',
      'quarter',
      'eighth',
      'sixteenth',
      '16th',
      '32nd',
    }.contains(type)) {
      return base;
    }
    final divisor = 1 << dots;
    return base * MusicalTime(divisor * 2 - 1, divisor);
  }

  static TimeSignature? activeMeter(Score score, int part, int measure) {
    final measures = score.parts[part].measures;
    for (var i = measure; i >= 0; i--) {
      if (measures[i].timeSignature case final meter?) return meter;
    }
    return null;
  }

  static KeySignature? activeKey(Score score, int part, int measure) {
    final measures = score.parts[part].measures;
    for (var i = measure; i >= 0; i--) {
      if (measures[i].keySignature case final key?) return key;
    }
    return null;
  }

  static MusicalTime meterLength(TimeSignature? meter) =>
      meter == null || meter.beatType <= 0 || meter.beats <= 0
      ? MusicalTime.zero
      : MusicalTime(meter.beats * 4, meter.beatType);

  MeasureTimeline measure(
    Score score,
    int partIndex,
    int measureIndex, {
    List<ScoreSymbol>? symbols,
    Map<int, MusicalTime> writtenOverrides = const {},
  }) {
    final current = score.parts[partIndex].measures[measureIndex];
    final source = score.musicXmlSource;
    final context = source == null
        ? null
        : (_sourceContexts[source] ??= _SourceTimingContext(source));
    final original =
        context?.measures[(score.parts[partIndex].id, current.reviewId)];
    if (original == null) {
      return _legacy(symbols ?? current.symbols, writtenOverrides);
    }
    final currentSymbols = symbols ?? current.symbols;
    final sameSequence =
        original.$2.symbols.length == currentSymbols.length &&
        List.generate(
          currentSymbols.length,
          (i) => _id(currentSymbols[i]) == _id(original.$2.symbols[i]),
        ).every((same) => same);
    if (!sameSequence) {
      if (source!.requiresPreservation) {
        throw const ScoreTimelineException(
          'Playback cannot preserve this imported bar after adding, removing or moving symbols yet. '
          'Undo those changes to play it. Your project retains the original notation.',
        );
      }
      return _legacy(currentSymbols, writtenOverrides);
    }
    // A staff split from a multi-staff <part> reads that part's events for
    // its own staff.
    final partId = score.parts[partIndex].id;
    final sourcePartId = context!.sourcePartIds[partId] ?? partId;
    var events =
        context.events[(sourcePartId, original.$1)] ??
        const <SourceScoreEvent>[];
    if (context.multiStaffParts.contains(sourcePartId)) {
      final staff = context.staves[partId];
      events = [
        for (final e in events)
          if (e.staff == staff) e,
      ];
    }
    final currentById = {
      for (final (i, s) in currentSymbols.indexed) _id(s): (i, s),
    };
    final previousById = {for (final s in original.$2.symbols) _id(s): s};
    final shifts = <VoiceLane, MusicalTime>{};
    final chordShifts = <VoiceLane, MusicalTime>{};
    final result = <TimedScoreSymbol>[];
    for (final event in events) {
      final id =
          context.bindings[(event.partId, event.measureIndex, event.noteIndex)];
      final currentSymbol = currentById[id];
      final previous = previousById[id];
      final eventLane = (event.voice, event.staff);
      var duration = event.duration;
      if (currentSymbol != null && previous != null) {
        if (lane(previous) != lane(currentSymbol.$2) ||
            (previous is Note && previous.isChordTone) !=
                (currentSymbol.$2 is Note &&
                    (currentSymbol.$2 as Note).isChordTone)) {
          throw const ScoreTimelineException(
            'Playback does not yet support changing this imported voice or chord structure.',
          );
        }
        final oldWritten = writtenDuration(previous);
        final newWritten =
            writtenOverrides[currentSymbol.$1] ??
            writtenDuration(currentSymbol.$2);
        if (!oldWritten.isZero) {
          duration = event.duration * newWritten / oldWritten;
        }
      }
      final shift = event.isChordTone
          ? chordShifts[eventLane] ?? MusicalTime.zero
          : shifts[eventLane] ?? MusicalTime.zero;
      result.add(
        TimedScoreSymbol(
          symbolIndex: currentSymbol?.$1,
          symbol: currentSymbol?.$2,
          onset: event.onset + shift,
          duration: duration,
          lane: eventLane,
          isChordTone: event.isChordTone,
        ),
      );
      if (!event.isChordTone) {
        chordShifts[eventLane] = shift;
        shifts[eventLane] = shift + duration - event.duration;
      }
    }
    return MeasureTimeline(result);
  }

  MeasureTimeline _legacy(
    List<ScoreSymbol> symbols,
    Map<int, MusicalTime> overrides,
  ) {
    final cursors = <VoiceLane, MusicalTime>{};
    final chordOnsets = <VoiceLane, MusicalTime>{};
    final result = <TimedScoreSymbol>[];
    for (final (i, symbol) in symbols.indexed) {
      if (symbol is! Note && symbol is! Rest) continue;
      final voice = lane(symbol);
      final duration = overrides[i] ?? writtenDuration(symbol);
      final chord =
          symbol is Note &&
          symbol.isChordTone &&
          chordOnsets.containsKey(voice);
      final onset = chord
          ? chordOnsets[voice]!
          : cursors[voice] ?? MusicalTime.zero;
      result.add(
        TimedScoreSymbol(
          symbolIndex: i,
          symbol: symbol,
          onset: onset,
          duration: duration,
          lane: voice,
          isChordTone: chord,
        ),
      );
      if (!chord) {
        chordOnsets[voice] = onset;
        cursors[voice] = onset + duration;
      }
    }
    return MeasureTimeline(result);
  }

  /// The order [bars] play in, by index: repeats, first and second endings,
  /// D.C., D.S., Fine and To Coda as MuseScore Studio plays them. A repeat
  /// goes round as many times as its highest ending number (at least
  /// twice); after a D.C. or D.S. repeats are not taken again and only the
  /// last ending plays.
  static List<int> playOrder(List<Measure> bars) {
    final n = bars.length;
    final order = <int>[];
    var i = 0, repeatStart = 0, pass = 1;
    var returning = false, jumped = false, toFine = false, toCoda = false;
    int endingEnd(int start) {
      for (var k = start; k < n; k++) {
        if (bars[k].endingEnd != null) return k;
      }
      return start;
    }

    // The highest ending number from the repeat's start through the run of
    // endings that follows bar [at].
    int highestEnding(int at) {
      var highest = 0;
      for (var k = repeatStart; k < n; k++) {
        if (k > at && bars[k].endingStart.isEmpty) break;
        for (final number in bars[k].endingStart) {
          if (number > highest) highest = number;
        }
        if (k > at) k = endingEnd(k);
      }
      return highest;
    }

    while (i < n && order.length < n * 8 + 8) {
      final bar = bars[i];
      if (bar.leftBarlineType == BarlineType.repeatStart && !returning) {
        repeatStart = i;
        pass = 1;
      }
      returning = false;
      if (bar.endingStart.isNotEmpty) {
        final end = endingEnd(i);
        final last = end + 1 >= n || bars[end + 1].endingStart.isEmpty;
        if (jumped ? !last : !bar.endingStart.contains(pass)) {
          i = end + 1;
          continue;
        }
      }
      order.add(i);
      if (bar.rightBarlineType == BarlineType.repeatEnd && !jumped) {
        final times = highestEnding(i) < 2 ? 2 : highestEnding(i);
        if (pass < times) {
          pass++;
          i = repeatStart;
          returning = true;
          continue;
        }
        pass = 1;
      }
      if (toFine && bar.navigation.contains(NavigationMark.fine)) break;
      if (toCoda && bar.navigation.contains(NavigationMark.toCoda)) {
        final coda = bars.indexWhere(
          (b) => b.navigation.contains(NavigationMark.coda),
          i + 1,
        );
        if (coda >= 0) {
          toCoda = false;
          i = coda;
          continue;
        }
      }
      final jump = bar.navigation.where((m) => m.isJump).firstOrNull;
      if (jump != null && !jumped) {
        jumped = true;
        toFine = jump.alFine;
        toCoda = jump.alCoda;
        final segno = bars.indexWhere(
          (b) => b.navigation.contains(NavigationMark.segno),
        );
        i = jump.toSegno && segno >= 0 ? segno : 0;
        pass = 1;
        continue;
      }
      i++;
    }
    return order;
  }

  /// [unrollRepeats] plays repeats and jumps (see [playOrder]); without it
  /// bars play once each in written order.
  ScoreTimeline build(Score score, {bool unrollRepeats = true}) {
    final source = score.musicXmlSource;
    if (source != null &&
        score.playbackLayout == ScorePlaybackLayout.simultaneousParts &&
        (_sourceContexts[source] ??= _SourceTimingContext(
          source,
        )).hasOmittedTimewiseParts) {
      throw const ScoreTimelineException(
        'Playback does not yet support timewise scores with omitted part bars. '
        'The original notation is retained in your project.',
      );
    }
    final result = <ScoreTimelineMeasure>[];
    var cursor = MusicalTime.zero;
    if (score.playbackLayout == ScorePlaybackLayout.sequentialStaves) {
      // Scanned staves are lines of one part: repeats run across them.
      final bars = [
        for (final (p, part) in score.parts.indexed)
          for (var m = 0; m < part.measures.length; m++) (p, m),
      ];
      final order = unrollRepeats
          ? playOrder([
              for (final (p, m) in bars) score.parts[p].measures[m],
            ])
          : [for (var k = 0; k < bars.length; k++) k];
      for (final k in order) {
        final (p, m) = bars[k];
        final timing = measure(score, p, m);
        final duration = timing.duration.isZero
            ? meterLength(activeMeter(score, p, m))
            : timing.duration;
        result.add(
          ScoreTimelineMeasure(
            partIndex: p,
            measureIndex: m,
            onset: cursor,
            duration: duration,
            timeline: timing,
          ),
        );
        cursor = cursor + duration;
      }
    } else {
      final longest = score.parts.fold(
        <Measure>[],
        (max, p) => p.measures.length > max.length ? p.measures : max,
      );
      final order = unrollRepeats
          ? playOrder(longest)
          : [for (var m = 0; m < longest.length; m++) m];
      var inheritedMeter = MusicalTime.zero;
      for (final m in order) {
        final group = <(int, MeasureTimeline)>[];
        var content = MusicalTime.zero, meter = MusicalTime.zero;
        for (final (p, part) in score.parts.indexed) {
          if (m >= part.measures.length) continue;
          final timing = measure(score, p, m);
          group.add((p, timing));
          if (timing.duration.compareTo(content) > 0) content = timing.duration;
          final nominal = meterLength(activeMeter(score, p, m));
          if (nominal.compareTo(meter) > 0) meter = nominal;
        }
        if (meter.isZero) meter = inheritedMeter;
        inheritedMeter = meter;
        final duration =
            m == 0 && !content.isZero && content.compareTo(meter) < 0
            ? content
            : content.compareTo(meter) > 0
            ? content
            : meter;
        for (final (p, timing) in group) {
          result.add(
            ScoreTimelineMeasure(
              partIndex: p,
              measureIndex: m,
              onset: cursor,
              duration: duration,
              timeline: timing,
            ),
          );
        }
        cursor = cursor + duration;
      }
    }
    return ScoreTimeline(measures: result, duration: cursor);
  }

  static String? _id(ScoreSymbol symbol) => switch (symbol) {
    Note(:final reviewId) || Rest(:final reviewId) => reviewId,
    _ => null,
  };
}

class _SourceTimingContext {
  _SourceTimingContext(MusicXmlSource source) {
    final baseline = Score.fromJson(
      jsonDecode(source.baselineJson) as Map<String, dynamic>,
    );
    // The editable projection has part-local indices. An omitted timewise
    // part would otherwise make its next bar sound one global bar too early.
    final root = XmlDocument.parse(source.xml).rootElement;
    String? first;
    for (final part in baseline.parts) {
      if (!part.joinsPrevious) first = part.id;
      sourcePartIds[part.id] = first ?? part.id;
      staves[part.id] = part.staff;
      if (part.joinsPrevious && first != null) multiStaffParts.add(first);
    }
    final partIds = {
      for (final part in baseline.parts)
        if (!part.joinsPrevious) part.id,
    };
    hasOmittedTimewiseParts =
        root.name.local == 'score-timewise' &&
        root
            .findElements('measure')
            .any(
              (measure) => !measure
                  .findElements('part')
                  .map((part) => part.getAttribute('id'))
                  .toSet()
                  .containsAll(partIds),
            );
    for (final part in baseline.parts) {
      for (final (m, measure) in part.measures.indexed) {
        measures[(part.id, measure.reviewId)] = (m, measure);
      }
    }
    for (final event in source.events) {
      events
          .putIfAbsent((event.partId, event.measureIndex), () => [])
          .add(event);
    }
    for (final binding in source.bindings) {
      bindings[(binding.partId, binding.measureIndex, binding.noteIndex)] =
          binding.symbolId;
    }
  }
  final measures = <(String, String?), (int, Measure)>{};

  /// Each projected part's source `<part>` id, staff number, and the source
  /// parts written on several staves.
  final sourcePartIds = <String, String>{};
  final staves = <String, int>{};
  final multiStaffParts = <String>{};
  late final bool hasOmittedTimewiseParts;
  final events = <(String, int), List<SourceScoreEvent>>{};
  final bindings = <(String, int, int), String>{};
}
