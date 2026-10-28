import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/measure.dart';
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

  ScoreTimeline build(Score score) {
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
      for (final (p, part) in score.parts.indexed) {
        for (var m = 0; m < part.measures.length; m++) {
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
      }
    } else {
      final count = score.parts.fold(
        0,
        (max, p) => p.measures.length > max ? p.measures.length : max,
      );
      var inheritedMeter = MusicalTime.zero;
      for (var m = 0; m < count; m++) {
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
