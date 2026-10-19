import '../models/beam_grouping.dart';
import '../models/clef.dart';
import '../models/key_signature.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/note_value.dart';
import '../models/part.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/score_symbol.dart';
import '../models/time_signature.dart';
import 'accidentals.dart';

/// What a [NotationIssue] is about. These are the paper's checks: unsure
/// detections, missing parts of the notation, misplaced accidentals, wrong
/// beat totals and a time signature the bars do not follow.
enum NotationIssueKind {
  lowConfidence,
  missingComponent,
  misplacedAccidental,
  beatTotal,
  timeSignature,
}

/// One problem found by [NotationChecker.check], with an optional fix the
/// user can accept. A fix is a pure function of the score, so accepting it
/// goes through the editor's undo stack like any other edit.
class NotationIssue {
  const NotationIssue({
    required this.kind,
    required this.partIndex,
    required this.measureIndex,
    this.symbolIndex,
    required this.message,
    this.fixLabel,
    this.fix,
  });

  final NotationIssueKind kind;
  final int partIndex;
  final int measureIndex;

  /// The symbol the issue is about; null when it is about the whole bar.
  final int? symbolIndex;
  final String message;

  /// What accepting the issue does ("Fill with rests"); null when the issue
  /// can only be reviewed and edited by hand.
  final String? fixLabel;
  final Score Function(Score score)? fix;

  bool get hasFix => fix != null;

  /// Identifies the issue across re-checks, so a dismissed issue stays
  /// dismissed while the score is edited elsewhere.
  String get key =>
      '${kind.name}:$partIndex:$measureIndex:${symbolIndex ?? '-'}:$message';
}

/// Rule-based check of a reconstructed score. It reads the score only; every
/// change is a [NotationIssue.fix] the user accepts or rejects.
class NotationChecker {
  NotationChecker._();

  /// Detections below this are flagged for review. On model B6's test
  /// photos about half of the detections under 0.6 are wrong, against 2%
  /// above 0.8.
  static const minConfidence = 0.6;

  static const _eps = 1e-6;

  /// Time signatures the editor offers, by bar length in quarter notes.
  static final _meters = <double, TimeSignature>{
    1.5: TimeSignature(beats: 3, beatType: 8),
    2.0: TimeSignature(beats: 2, beatType: 4),
    3.0: TimeSignature(beats: 3, beatType: 4),
    4.0: TimeSignature(beats: 4, beatType: 4),
  };

  static List<NotationIssue> check(Score score) {
    final issues = <NotationIssue>[];
    if (score.parts.isEmpty) return issues;

    _checkClefs(score, issues);
    // Bars explained by a time-signature issue are not reported one by one.
    final explained = _checkTimeSignatures(score, issues);

    for (var p = 0; p < score.parts.length; p++) {
      final part = score.parts[p];
      final lastFilled = part.measures.lastIndexWhere(
        (m) => _musical(m).isNotEmpty,
      );
      final accidentals = _AccidentalState();
      for (var m = 0; m < part.measures.length; m++) {
        final measure = part.measures[m];
        accidentals.startMeasure(measure);
        _checkSymbols(score, p, m, measure, accidentals, issues);
        if (!explained.contains(m)) {
          _checkBeats(score, p, m, lastFilled, issues);
        }
      }
    }
    return issues;
  }

  // ---------------------------------------------------------------------------
  // Rules
  // ---------------------------------------------------------------------------

  static void _checkClefs(Score score, List<NotationIssue> issues) {
    for (var p = 0; p < score.parts.length; p++) {
      final part = score.parts[p];
      if (part.measures.isEmpty || part.measures.any((m) => m.clef != null)) {
        continue;
      }
      if (part.measures.every((m) => m.symbols.isEmpty)) continue;
      final borrowed =
          [
                for (var k = p - 1; k >= 0; k--) k,
                for (var k = p + 1; k < score.parts.length; k++) k,
              ]
              .map(
                (k) => score.parts[k].measures
                    .map((m) => m.clef)
                    .whereType<Clef>()
                    .firstOrNull,
              )
              .whereType<Clef>()
              .firstOrNull;
      final clef = borrowed ?? const Clef(sign: 'G', line: 2);
      issues.add(
        NotationIssue(
          kind: NotationIssueKind.missingComponent,
          partIndex: p,
          measureIndex: 0,
          message: 'Staff ${p + 1} has no clef.',
          fixLabel: 'Use ${clef.sign == 'F' ? 'bass' : 'treble'} clef',
          fix: (s) => s.setMeasureClef(p, 0, clef),
        ),
      );
    }
  }

  /// Returns the measure indices whose beat totals a time-signature issue
  /// already covers.
  static Set<int> _checkTimeSignatures(
    Score score,
    List<NotationIssue> issues,
  ) {
    final explained = <int>{};
    final first = score.parts.first;
    final measureCount = first.measures.length;

    // Parts that disagree with the first part.
    for (var p = 1; p < score.parts.length; p++) {
      final part = score.parts[p];
      for (var m = 0; m < part.measures.length; m++) {
        final own = part.measures[m].timeSignature;
        if (own == null) continue;
        final expected = _meterAt(first, m);
        if (expected == null || expected == own) continue;
        issues.add(
          NotationIssue(
            kind: NotationIssueKind.timeSignature,
            partIndex: p,
            measureIndex: m,
            message:
                'Staff ${p + 1} is in ${_meterText(own)} here but staff 1 is '
                'in ${_meterText(expected)}.',
            fixLabel: 'Use ${_meterText(expected)}',
            fix: (s) => s.setTimeSignatureAt(m, expected),
          ),
        );
      }
    }

    // Sections between the first part's time signatures.
    final starts = <int>[
      for (var m = 0; m < measureCount; m++)
        if (m == 0 || first.measures[m].timeSignature != null) m,
    ];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1] : measureCount;
      final written = _meterAt(first, start);
      final totals = <double>[];
      for (final part in score.parts) {
        final lastFilled = part.measures.lastIndexWhere(
          (m) => _musical(m).isNotEmpty,
        );
        for (var m = start; m < end && m < part.measures.length; m++) {
          // A pickup bar and the last bar may be short on purpose.
          if (m == 0 || m == lastFilled) continue;
          if (_musical(part.measures[m]).isEmpty) continue;
          totals.add(_total(part.measures[m]));
        }
      }
      final common = _mostCommon(totals);

      if (written == null) {
        // No time signature at all: suggest the bars' own length.
        if (start != 0 || totals.isEmpty) continue;
        final meter = common == null
            ? const TimeSignature(beats: 4, beatType: 4)
            : _meters[common.value] ??
                  const TimeSignature(beats: 4, beatType: 4);
        explained.addAll([for (var m = start; m < end; m++) m]);
        issues.add(
          NotationIssue(
            kind: NotationIssueKind.timeSignature,
            partIndex: 0,
            measureIndex: 0,
            message: 'No time signature was read.',
            fixLabel: 'Set ${_meterText(meter)}',
            fix: (s) => s.setTimeSignatureAt(0, meter),
          ),
        );
        continue;
      }

      if (totals.length < 3 || common == null) continue;
      final capacity = _capacity(written);
      final off = totals.where((t) => (t - capacity).abs() > _eps).length;
      if (off < totals.length * 0.6 || common.count < totals.length * 0.6) {
        continue;
      }
      final meter = _meters[common.value];
      if (meter == null || (common.value - capacity).abs() < _eps) continue;
      explained.addAll([for (var m = start; m < end; m++) m]);
      issues.add(
        NotationIssue(
          kind: NotationIssueKind.timeSignature,
          partIndex: 0,
          measureIndex: start,
          message:
              '${common.count} of ${totals.length} bars hold '
              '${_beatsText(common.value, written)} instead of '
              '${_meterText(written)}.',
          fixLabel: 'Change to ${_meterText(meter)}',
          fix: (s) => s.setTimeSignatureAt(start, meter),
        ),
      );
    }
    return explained;
  }

  static void _checkSymbols(
    Score score,
    int p,
    int m,
    Measure measure,
    _AccidentalState accidentals,
    List<NotationIssue> issues,
  ) {
    final symbols = measure.symbols;
    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      final confidence = switch (symbol) {
        Note(:final confidence) => confidence,
        Rest(:final confidence) => confidence,
        _ => null,
      };
      if (confidence != null && confidence < minConfidence) {
        issues.add(
          NotationIssue(
            kind: NotationIssueKind.lowConfidence,
            partIndex: p,
            measureIndex: m,
            symbolIndex: i,
            message:
                'Unsure about this ${_symbolName(symbol)} '
                '(${(confidence * 100).round()}%). Check it against the page.',
          ),
        );
      }

      if (symbol is! Note) continue;
      final repeated = accidentals.redundant(symbol);
      if (repeated != null) {
        issues.add(
          NotationIssue(
            kind: NotationIssueKind.misplacedAccidental,
            partIndex: p,
            measureIndex: m,
            symbolIndex: i,
            message:
                'The ${_alterText(symbol.alter!)} on ${symbol.step}'
                '${symbol.octave} changes nothing: $repeated.',
            fixLabel: 'Remove accidental',
            fix: (s) =>
                _replaceNote(s, p, m, i, (n) => _copyNote(n, alter: null)),
          ),
        );
      }
    }

    // A beamed note needs a beamed neighbour; alone, its partner or the
    // beam was missed.
    for (final group in _beamGroups(symbols)) {
      if (group.length != 1) continue;
      final i = group.single;
      issues.add(
        NotationIssue(
          kind: NotationIssueKind.missingComponent,
          partIndex: p,
          measureIndex: m,
          symbolIndex: i,
          message:
              'This beamed ${_symbolName(symbols[i])} has no note to share '
              'its beam with.',
          fixLabel: 'Draw with a flag',
          fix: (s) =>
              _replaceNote(s, p, m, i, (n) => _copyNote(n, beamed: false)),
        ),
      );
    }
  }

  static void _checkBeats(
    Score score,
    int p,
    int m,
    int lastFilled,
    List<NotationIssue> issues,
  ) {
    final part = score.parts[p];
    final measure = part.measures[m];
    final musical = _musical(measure);
    if (musical.isEmpty) return;
    final meter = _meterAt(part, m) ?? _meterAt(score.parts.first, m);
    if (meter == null) return;
    final capacity = _capacity(meter);
    final total = _total(measure);
    final diff = total - capacity;
    if (diff.abs() <= _eps) return;

    final where = 'Bar ${m + 1}';
    if (diff < 0) {
      // A short first bar is a pickup.
      if (m == 0 && part.measures.length > 1) return;
      String? label;
      Score Function(Score)? fix;
      // The barline came early: the start of the next bar belongs here.
      if (m + 1 < part.measures.length) {
        final next = part.measures[m + 1];
        final nextOver =
            _total(next) - _capacity(_meterAt(part, m + 1) ?? meter);
        final head = _headFor(next.symbols, -diff);
        if (head != null && (nextOver + diff).abs() <= _eps) {
          label =
              'Move ${_countText(next.symbols, 0, head)} of bar '
              '${m + 2} here';
          fix = (s) => _moveHead(s, p, m + 1, head);
        }
      }
      if (fix == null) {
        final rests = _restsFor(-diff);
        if (rests != null) {
          label = 'Fill with rests';
          fix = (s) => _withMeasureSymbols(s, p, m, [
            ...s.parts[p].measures[m].symbols,
            ...rests,
          ]);
        }
      }
      issues.add(
        NotationIssue(
          kind: NotationIssueKind.beatTotal,
          partIndex: p,
          measureIndex: m,
          message:
              '$where has ${_beatsText(total, meter)}; a bar of '
              '${_meterText(meter)} needs ${_beatsText(capacity, meter)}.',
          fixLabel: label,
          fix: fix,
        ),
      );
      return;
    }

    final over = diff;
    String? label;
    Score Function(Score)? fix;

    // 1. A symbol was detected twice.
    final symbols = measure.symbols;
    for (var i = 1; i < symbols.length && fix == null; i++) {
      if (_length(symbols[i]) <= 0 ||
          (_length(symbols[i]) - over).abs() > _eps ||
          (symbols[i].toJson()
                    ..remove('reviewId')
                    ..remove('source'))
                  .toString() !=
              (symbols[i - 1].toJson()
                    ..remove('reviewId')
                    ..remove('source'))
                  .toString()) {
        continue;
      }
      label = 'Remove the repeated ${_symbolName(symbols[i])}';
      fix = (s) => s.deleteSymbolAt(p, m, i);
    }

    // 2. The barline came late: the start of this bar belongs to the
    // previous one, which is short by as much.
    final head = _headFor(symbols, over);
    if (fix == null && head != null && m > 0) {
      final previous = part.measures[m - 1];
      final room = _capacity(_meterAt(part, m - 1) ?? meter) - _total(previous);
      if (_musical(previous).isNotEmpty && (room - over).abs() <= _eps) {
        label = 'Move ${_countText(symbols, 0, head)} to bar $m';
        fix = (s) => _moveHead(s, p, m, head);
      }
    }

    // 3. The barline came early: the extra notes fit the next bar.
    final tail = _tailFor(measure.symbols, over);
    if (fix == null && tail != null && m + 1 < part.measures.length) {
      final next = part.measures[m + 1];
      final nextMeter = _meterAt(part, m + 1) ?? meter;
      final room = _capacity(nextMeter) - _total(next);
      if (_musical(next).isNotEmpty && (room - over).abs() <= _eps) {
        label =
            'Move ${_countText(symbols, tail, symbols.length, last: true)} '
            'to bar ${m + 2}';
        fix = (s) {
          final from = s.parts[p].measures[m].symbols;
          final to = s.parts[p].measures[m + 1].symbols;
          final moved = _withMeasureSymbols(s, p, m, from.sublist(0, tail));
          return _withMeasureSymbols(moved, p, m + 1, [
            ...from.sublist(tail),
            ...to,
          ]);
        };
      }
    }

    // 4. A barline was missed: the bar splits evenly into whole bars.
    if (fix == null) {
      final chunks = _splitAt(measure.symbols, capacity);
      if (chunks != null) {
        label = 'Split into ${chunks.length} bars';
        fix = (s) => _splitMeasure(s, p, m, chunks);
      }
    }

    // 5. The last note was read too long.
    if (fix == null) {
      final last = measure.symbols.lastIndexWhere(
        (s) => (s is Note && !s.isChordTone) || s is Rest,
      );
      if (last >= 0) {
        final symbol = measure.symbols[last];
        final length = _length(symbol);
        final value = _valueFor(length - over);
        if (value != null) {
          label =
              'Shorten the last ${_symbolName(symbol)} to '
              '${value.dots > 0 ? 'a dotted ' : 'a '}${value.type}';
          fix = (s) => _replaceSymbol(
            s,
            p,
            m,
            last,
            (old) => _withValue(old, value.type, value.dots),
          );
        }
      }
    }

    issues.add(
      NotationIssue(
        kind: NotationIssueKind.beatTotal,
        partIndex: p,
        measureIndex: m,
        message:
            '$where has ${_beatsText(total, meter)}; a bar of '
            '${_meterText(meter)} holds only ${_beatsText(capacity, meter)}.',
        fixLabel: label,
        fix: fix,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Measuring
  // ---------------------------------------------------------------------------

  /// Notes (not chord tones) and rests: the symbols that take time.
  static List<ScoreSymbol> _musical(Measure measure) => [
    for (final s in measure.symbols)
      if ((s is Note && !s.isChordTone) || s is Rest) s,
  ];

  static double _length(ScoreSymbol s) => switch (s) {
    Note(:final type, :final dots, :final duration, :final isChordTone) =>
      isChordTone ? 0 : quarterLength(type, dots, duration),
    Rest(:final type, :final dots, :final duration) => quarterLength(
      type,
      dots,
      duration,
    ),
    _ => 0,
  };

  static double _total(Measure measure) =>
      measure.symbols.fold(0.0, (sum, s) => sum + _length(s));

  static double _capacity(TimeSignature t) => t.beats * 4 / t.beatType;

  static TimeSignature? _meterAt(Part part, int measureIndex) {
    for (var m = measureIndex; m >= 0; m--) {
      if (m >= part.measures.length) continue;
      final t = part.measures[m].timeSignature;
      if (t != null) return t;
    }
    return null;
  }

  static ({double value, int count})? _mostCommon(List<double> values) {
    final counts = <double, int>{};
    for (final v in values) {
      final key = (v * 16).round() / 16;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (value: best.key, count: best.value);
  }

  /// Index where the trailing symbols adding up to exactly [length] start,
  /// or null when no tail does.
  static int? _tailFor(List<ScoreSymbol> symbols, double length) {
    var sum = 0.0;
    for (var i = symbols.length - 1; i > 0; i--) {
      sum += _length(symbols[i]);
      if ((sum - length).abs() <= _eps) {
        // Keep a chord's tones with their note.
        var start = i;
        while (start > 0 &&
            symbols[start] is Note &&
            (symbols[start] as Note).isChordTone) {
          start--;
        }
        return start == i ? i : null;
      }
      if (sum > length + _eps) return null;
    }
    return null;
  }

  /// End (exclusive) of the leading symbols adding up to exactly [length],
  /// with the chord tones of the last one; null when no head does.
  static int? _headFor(List<ScoreSymbol> symbols, double length) {
    var sum = 0.0;
    for (var i = 0; i < symbols.length - 1; i++) {
      sum += _length(symbols[i]);
      if ((sum - length).abs() <= _eps) {
        var end = i + 1;
        while (end < symbols.length &&
            symbols[end] is Note &&
            (symbols[end] as Note).isChordTone) {
          end++;
        }
        return end < symbols.length ? end : null;
      }
      if (sum > length + _eps) return null;
    }
    return null;
  }

  /// Moves the first [count] symbols of bar [m] to the end of bar m - 1.
  static Score _moveHead(Score s, int p, int m, int count) {
    final from = s.parts[p].measures[m].symbols;
    final to = s.parts[p].measures[m - 1].symbols;
    final moved = _withMeasureSymbols(s, p, m, from.sublist(count));
    return _withMeasureSymbols(moved, p, m - 1, [
      ...to,
      ...from.sublist(0, count),
    ]);
  }

  /// "the first note", "the last 2 notes": the notes and rests in
  /// symbols[start, end).
  static String _countText(
    List<ScoreSymbol> symbols,
    int start,
    int end, {
    bool last = false,
  }) {
    final n = symbols.sublist(start, end).where((s) => _length(s) > 0).length;
    final which = last ? 'last' : 'first';
    return n == 1 ? 'the $which note' : 'the $which $n notes';
  }

  /// The symbols cut into whole bars of [capacity], or null when a note
  /// crosses a bar line or the bar is not a whole number of bars long.
  static List<List<ScoreSymbol>>? _splitAt(
    List<ScoreSymbol> symbols,
    double capacity,
  ) {
    final chunks = <List<ScoreSymbol>>[[]];
    var sum = 0.0;
    for (final s in symbols) {
      if ((sum - capacity).abs() <= _eps && _length(s) > 0) {
        chunks.add([]);
        sum = 0;
      }
      chunks.last.add(s);
      sum += _length(s);
      if (sum > capacity + _eps) return null;
    }
    if ((sum - capacity).abs() > _eps || chunks.length < 2) return null;
    return chunks;
  }

  static const _plainValues = [
    ('whole', 4.0),
    ('half', 2.0),
    ('quarter', 1.0),
    ('eighth', 0.5),
    ('sixteenth', 0.25),
  ];

  /// The written value of a note or rest lasting [length] quarters.
  static ({String type, int dots})? _valueFor(double length) {
    for (final (type, base) in _plainValues) {
      if ((length - base).abs() <= _eps) return (type: type, dots: 0);
      if ((length - base * 1.5).abs() <= _eps && type != 'sixteenth') {
        return (type: type, dots: 1);
      }
    }
    return null;
  }

  /// Rests filling [length] quarters, longest first; null when sixteenths
  /// cannot fill it.
  static List<Rest>? _restsFor(double length) {
    final rests = <Rest>[];
    var left = length;
    for (final (type, base) in _plainValues) {
      while (left >= base - _eps) {
        rests.add(Rest(duration: (base * 2).round(), type: type));
        left -= base;
      }
    }
    return left.abs() <= _eps ? rests : null;
  }

  static List<List<int>> _beamGroups(List<ScoreSymbol> symbols) =>
      BeamGrouping.groups(symbols);

  // ---------------------------------------------------------------------------
  // Fixes
  // ---------------------------------------------------------------------------

  static Score _replaceSymbol(
    Score s,
    int p,
    int m,
    int i,
    ScoreSymbol Function(ScoreSymbol old) change,
  ) {
    final old = s.getSymbolAt(p, m, i);
    return old == null ? s : s.replaceSymbolAt(p, m, i, change(old));
  }

  static Score _replaceNote(
    Score s,
    int p,
    int m,
    int i,
    Note Function(Note old) change,
  ) => _replaceSymbol(s, p, m, i, (old) => old is Note ? change(old) : old);

  static ScoreSymbol _withValue(ScoreSymbol old, String type, int dots) {
    final duration = (quarterLength(type, dots, 0) * 2).round();
    return switch (old) {
      Note() => _copyNote(old, type: type, dots: dots, duration: duration),
      Rest() => Rest(
        duration: duration,
        type: type,
        voice: old.voice,
        staff: old.staff,
        dots: dots,
        confidence: old.confidence,
        reviewId: old.reviewId,
        source: old.source,
      ),
      _ => old,
    };
  }

  static const Object _keep = Object();

  static Note _copyNote(
    Note n, {
    Object? alter = _keep,
    bool? beamed,
    String? type,
    int? dots,
    int? duration,
  }) => Note(
    step: n.step,
    octave: n.octave,
    alter: identical(alter, _keep) ? n.alter : alter as int?,
    duration: duration ?? n.duration,
    type: type ?? n.type,
    voice: n.voice,
    staff: n.staff,
    beamed: beamed ?? n.beamed,
    beams: beamed == false ? const {} : n.beams,
    dots: dots ?? n.dots,
    isChordTone: n.isChordTone,
    confidence: n.confidence,
    reviewId: n.reviewId,
    source: n.source,
  );

  static Measure _measureWith(
    Measure m,
    List<ScoreSymbol> symbols, {
    int? number,
  }) => Measure(
    number: number ?? m.number,
    reviewId: m.reviewId,
    source: m.source,
    clef: m.clef,
    timeSignature: m.timeSignature,
    keySignature: m.keySignature,
    symbols: symbols,
    startsNewPage: m.startsNewPage,
    startsNewSystem: m.startsNewSystem,
    leftBarlineType: m.leftBarlineType,
    rightBarlineType: m.rightBarlineType,
  );

  static Score _withParts(Score s, List<Part> parts) =>
      s.copyWith(parts: parts);

  static Score _withMeasureSymbols(
    Score s,
    int p,
    int m,
    List<ScoreSymbol> symbols,
  ) {
    final part = s.parts[p];
    final measures = [...part.measures];
    measures[m] = _measureWith(measures[m], symbols);
    final parts = [...s.parts];
    parts[p] = Part(id: part.id, name: part.name, measures: measures);
    return _withParts(s, parts);
  }

  /// Splits bar [m] of part [p] into [chunks]. The staff's trailing empty
  /// bars (padding) absorb the new ones; when there are not enough, the
  /// other parts get empty bars at the end so all parts stay equally long.
  static Score _splitMeasure(
    Score s,
    int p,
    int m,
    List<List<ScoreSymbol>> chunks,
  ) {
    final part = s.parts[p];
    final original = part.measures[m];
    final measures = [
      ...part.measures.sublist(0, m),
      _measureWith(original, chunks.first),
      for (final chunk in chunks.skip(1)) Measure(number: 0, symbols: chunk),
      ...part.measures.sublist(m + 1),
    ];
    var added = chunks.length - 1;
    while (added > 0 &&
        measures.length > m + chunks.length &&
        measures.last.symbols.isEmpty) {
      measures.removeLast();
      added--;
    }
    final target = measures.length;
    final parts = <Part>[
      for (var k = 0; k < s.parts.length; k++)
        () {
          final own = k == p ? measures : [...s.parts[k].measures];
          while (own.length < target) {
            own.add(Measure(number: 0, symbols: const []));
          }
          return Part(
            id: s.parts[k].id,
            name: s.parts[k].name,
            measures: [
              for (var i = 0; i < own.length; i++)
                _measureWith(own[i], own[i].symbols, number: i + 1),
            ],
          );
        }(),
    ];
    return _withParts(s, parts);
  }

  // ---------------------------------------------------------------------------
  // Wording
  // ---------------------------------------------------------------------------

  static String _meterText(TimeSignature t) => '${t.beats}/${t.beatType}';

  /// A length in the meter's own beats: "2½ beats" in 3/4, "5 eighths" in 3/8.
  static String _beatsText(double quarters, TimeSignature meter) {
    final unit = 4 / meter.beatType;
    final beats = quarters / unit;
    final whole = beats.floor();
    final frac = beats - whole;
    final fracText = switch ((frac * 4).round()) {
      0 => '',
      1 => '¼',
      2 => '½',
      3 => '¾',
      _ => '',
    };
    final number = whole == 0 && fracText.isNotEmpty
        ? fracText
        : '$whole$fracText';
    final noun = meter.beatType == 8 ? 'eighth' : 'beat';
    return beats == 1 ? '1 $noun' : '$number ${noun}s';
  }

  static String _alterText(int alter) => switch (alter) {
    1 => 'sharp',
    -1 => 'flat',
    0 => 'natural',
    2 => 'double sharp',
    -2 => 'double flat',
    _ => 'accidental',
  };

  static String _symbolName(ScoreSymbol s) => switch (s) {
    Note(:final type, :final dots) =>
      '${dots > 0 ? 'dotted ' : ''}${_typeName(type)} note',
    Rest(:final type, :final dots) =>
      '${dots > 0 ? 'dotted ' : ''}${_typeName(type)} rest',
    _ => 'symbol',
  };

  static String _typeName(String type) => type == '16th' ? 'sixteenth' : type;
}

/// Tracks which accidentals are in force, as [Accidentals] does for
/// playback, to find ones that change nothing. A courtesy accidental that
/// cancels one from the previous bar is allowed.
class _AccidentalState {
  KeySignature? _key;
  var _carried = <String, int>{};
  var _previous = <String, int>{};

  void startMeasure(Measure measure) {
    _key = measure.keySignature ?? _key;
    _previous = _carried;
    _carried = {};
  }

  /// Why [note]'s written accidental is redundant, or null when it is not.
  String? redundant(Note note) {
    final alter = note.alter;
    final pitch = '${note.step.toUpperCase()}${note.octave}';
    if (alter == null) return null;
    final inBar = _carried[pitch];
    final fromKey = Accidentals.keyAlter(_key, note.step);
    _carried[pitch] = alter;
    if (inBar != null) {
      return inBar == alter
          ? 'the same accidental is already in this bar'
          : null;
    }
    if (alter != fromKey) return null;
    final before = _previous[pitch];
    if (before != null && before != alter) return null; // courtesy
    return alter == 0
        ? '${note.step} is natural in this key'
        : 'the key signature already has it';
  }
}
