import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../../models/measure.dart';
import '../../models/clef.dart';
import '../../models/beam_grouping.dart';
import '../../models/musical_time.dart';
import '../../models/note.dart';
import '../../models/part.dart';
import '../../models/rest.dart';
import '../../models/score.dart';
import '../../models/score_symbol.dart';
import '../../services/score_timeline.dart';
import 'score_notation_metrics.dart';
import 'staff_pitch_mapper.dart';
import 'voice_layout.dart';
import 'score_display_projection.dart';

/// Shared engraving coordinates in staff units (12 units per staff space).
/// Musical time comes from the live timeline, including retained source gaps.
/// A column is shared by all staves; grace columns precede its timed column.
class EngravingLayout {
  EngravingLayout(
    List<List<Measure>> inputParts, {
    Score? score,
    int firstMeasure = 0,
  }) : parts = ScoreDisplayProjection.fromDisplayScore(score) == null
           ? _normalize(inputParts)
           : inputParts {
    final display = ScoreDisplayProjection.fromDisplayScore(score);
    final plain = Score(
      id: 'layout',
      title: '',
      composer: '',
      parts: [
        for (final (p, measures) in parts.indexed)
          Part(id: '$p', name: '', measures: measures),
      ],
    );
    final count = parts.fold(0, (n, p) => math.max(n, p.length));
    for (var m = 0; m < count; m++) {
      final measures = <Measure?>[
        for (final p in parts) m < p.length ? p[m] : null,
      ];
      final timelines = <MeasureTimeline>[];
      for (var p = 0; p < parts.length; p++) {
        if (m >= parts[p].length) {
          timelines.add(MeasureTimeline([]));
          continue;
        }
        try {
          final cell = display?.origin(p, m + firstMeasure);
          if (display != null && cell == null) {
            timelines.add(MeasureTimeline([]));
            continue;
          }
          timelines.add(
            const ScoreTimelineBuilder().measure(
              display?.source ?? score ?? plain,
              cell?.part ?? p,
              cell?.measure ?? m + (score == null ? 0 : firstMeasure),
            ),
          );
        } on ScoreTimelineException {
          // An unsupported source edit still needs an editable written preview.
          try {
            timelines.add(const ScoreTimelineBuilder().measure(plain, p, m));
          } on ScoreTimelineException {
            timelines.add(MeasureTimeline([]));
          }
        } on FormatException {
          timelines.add(MeasureTimeline([]));
        }
      }
      bars.add(BarEngraving(measures, timelines));
    }
  }
  final List<List<Measure>> parts;
  final bars = <BarEngraving>[];
  BarPlacement place(int index, double width, int perRow, double prefix) =>
      bars[index].place(
        width: width,
        inset: parts.fold(
          16.0,
          (inset, p) => index >= p.length
              ? inset
              : math.max(
                  inset,
                  ScoreNotationMetrics.laneInset(
                    timeInMeasure: ScoreNotationMetrics.timeSignatureInMeasure(
                      p,
                      index,
                      measureInRow: index % perRow,
                      rowPrefixWidth: prefix,
                    ),
                  ),
                ),
        ),
      );

  late final (double, double) clearance = verticalClearance(parts);
  static final _clearances = Expando<(double, double)>();
  static (double, double) verticalClearance(List<List<Measure>> parts) =>
      _clearances[parts] ??= _verticalClearance(parts);
  static (double, double) _verticalClearance(List<List<Measure>> parts) {
    var above = 0.0, below = 0.0;
    for (final measures in parts) {
      Clef? clef;
      for (final m in measures) {
        clef = m.clef ?? clef;
        final directions = stemDirections(m.copyWith(clef: clef));
        for (final (i, s) in m.symbols.indexed) {
          if (s is! Note) continue;
          final y = StaffPitchMapper.yForPitch(
            step: s.step,
            octave: s.octave,
            bottomLineY: 48,
            lineSpacing: 12,
            clefSign: clef?.layoutSign ?? 'G',
            clefLine: clef?.line ?? 2,
          );
          final grace = s.grace != null, scale = grace ? 0.65 : 1.0;
          final up = directions[i] ?? y > 24;
          final whole = {'whole', 'breve'}.contains(s.type);
          final stem = whole ? 6.0 : ScoreNotationMetrics.stemLengthFor(12);
          final marks = s.marks.isEmpty ? 0.0 : 16.0;
          final top = y - (up ? stem : 6) * scale - (up ? marks : 0);
          final bottom = y + (up ? 6 : stem) * scale + (!up ? marks : 0);
          above = math.max(above, -top - 24);
          below = math.max(below, bottom - 68);
        }
      }
    }
    return (above, below);
  }

  double get minimumBarWidth =>
      bars.fold(100.0, (n, b) => math.max(n, b.minimumWidth));

  static final _scores = Expando<EngravingLayout>();
  static EngravingLayout forScore(Score score) =>
      _scores[score] ??= EngravingLayout([
        for (final part in score.parts) part.measures,
      ], score: score);
  static List<List<Measure>> _normalize(List<List<Measure>> parts) => [
    for (final part in parts)
      () {
        Measure? previous;
        return [
          for (final m in part)
            () {
              final next = m.copyWith(
                clef: m.clef ?? previous?.clef,
                timeSignature: m.timeSignature ?? previous?.timeSignature,
                keySignature: m.keySignature ?? previous?.keySignature,
              );
              ScoreDisplayProjection.copyRowContext(m, next);
              previous = next;
              return next;
            }(),
        ];
      }(),
  ];
  static double noteY(Note n, Measure m) => StaffPitchMapper.yForPitch(
    step: n.step,
    octave: n.octave,
    bottomLineY: 48,
    lineSpacing: 12,
    clefSign: m.clef?.layoutSign ?? 'G',
    clefLine: m.clef?.line ?? 2,
  );
  static List<bool?> stemDirections(Measure m) {
    final symbols = m.symbols, voices = VoiceLayout.of(m.symbols);
    final result = <bool?>[
      for (final (i, s) in symbols.indexed)
        s is Note
            ? s.grace != null || (voices.stemUp(i) ?? noteY(s, m) > 24)
            : null,
    ];
    for (final beam in BeamGrouping.groups(
      symbols,
    ).where((g) => g.length > 1)) {
      final ys = [for (final i in beam) noteY(symbols[i] as Note, m)];
      final up =
          voices.stemUp(beam.first) ??
          ys.reduce((a, b) => a + b) / ys.length > 24;
      for (final i in beam) {
        result[i] = up;
      }
    }
    return result;
  }

  /// Text bounds use the same face/size as the editor and the PDF.
  static double textWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: ScoreNotationMetrics.textFontFamily,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

typedef EngravingColumn = (MusicalTime, int);

class BarEngraving {
  BarEngraving(this.measures, List<MeasureTimeline> timelines) {
    var end = MusicalTime.zero;
    for (final (p, measure) in measures.indexed) {
      final symbols = measure?.symbols ?? const <ScoreSymbol>[];
      if (timelines[p].duration.compareTo(end) > 0) end = timelines[p].duration;
      final timing = {
        for (final e in timelines[p].symbols)
          if (e.symbolIndex != null) e.symbolIndex!: e,
      };
      final graceRuns = <VoiceLane, int>{};
      final keys = List<EngravingColumn>.filled(symbols.length, (
        MusicalTime.zero,
        0,
      ));
      for (var i = symbols.length - 1; i >= 0; i--) {
        final s = symbols[i], e = timing[i];
        final lane = ScoreTimelineBuilder.lane(s);
        final grace = s is Note && s.grace != null;
        graceRuns[lane] = grace ? (graceRuns[lane] ?? 0) + 1 : 0;
        keys[i] = (e?.onset ?? MusicalTime.zero, grace ? -graceRuns[lane]! : 0);
        if (e != null && e.end.compareTo(end) > 0) end = e.end;
      }
      final meter = ScoreTimelineBuilder.meterLength(measure?.timeSignature);
      if (measure?.implicit != true && meter.compareTo(end) > 0) end = meter;
      staff.add(StaffEngraving(symbols, keys));
      for (final k in keys) {
        _ink.putIfAbsent(k, () => _ColumnInk());
      }
      for (final a in measure?.annotations ?? const <ScoreAnnotation>[]) {
        if (a.hidden) continue;
        final time = a.offset.isNegative ? MusicalTime.zero : a.offset;
        _ink.putIfAbsent((time, 0), () => _ColumnInk());
        if (time.compareTo(end) > 0) end = time;
      }
    }
    duration = end.isZero ? MusicalTime(4) : end;
    _ink.putIfAbsent((MusicalTime.zero, 0), () => _ColumnInk());
    _ink.putIfAbsent((duration, 0), () => _ColumnInk());
    columns = _ink.keys.toList()
      ..sort((a, b) {
        final t = a.$1.compareTo(b.$1);
        return t == 0 ? a.$2.compareTo(b.$2) : t;
      });
    for (final (p, part) in staff.indexed) {
      if (measures[p] == null) continue;
      final symbols = part.symbols;
      // Seconds in a chord alternate sides of the shared stem. Distinct
      // voices with touching heads move as a unit, retaining their stems.
      final groups = <EngravingColumn, List<int>>{};
      for (final (i, s) in symbols.indexed) {
        if (s is Note) groups.putIfAbsent(part.keys[i], () => []).add(i);
      }
      final directions = EngravingLayout.stemDirections(measures[p]!);
      for (final (i, up) in directions.indexed) {
        part.stemUps[i] = up;
      }
      for (final group in groups.values) {
        final lanes = <VoiceLane, List<int>>{};
        for (final i in group) {
          lanes
              .putIfAbsent(ScoreTimelineBuilder.lane(symbols[i]), () => [])
              .add(i);
        }
        final occupied = <(int, double)>[];
        for (final notes in lanes.values) {
          notes.sort(
            (a, b) =>
                pitch(symbols[a] as Note).compareTo(pitch(symbols[b] as Note)),
          );
          final root =
              notes
                  .where((i) => !(symbols[i] as Note).isChordTone)
                  .firstOrNull ??
              notes.first;
          final up = part.stemUps[root]!;
          final rootPitch = pitch(symbols[root] as Note);
          final low = pitch(symbols[notes.first] as Note),
              high = pitch(symbols[notes.last] as Note);
          final ordered = up ? notes : notes.reversed.toList();
          var previous = -1000, shifted = false;
          var voiceShift = 0.0;
          while (notes.any(
            (i) => occupied.any(
              (o) =>
                  (pitch(symbols[i] as Note) - o.$1).abs() <= 1 &&
                  (voiceShift - o.$2).abs() < 14,
            ),
          )) {
            voiceShift += 18;
          }
          for (final i in ordered) {
            final step = pitch(symbols[i] as Note);
            shifted = (step - previous).abs() == 1 ? !shifted : false;
            part.headOffsets[i] =
                voiceShift + (shifted ? (up ? 12.0 : -12.0) : 0);
            part.stemUps[i] = up;
            part.stemOffsets[i] = voiceShift + (up ? 6 : -6);
            part.stemStarts[i] = (rootPitch - (up ? low : high)) * 6.0;
            part.stemEnds[i] =
                (rootPitch - (up ? high : low)) * 6.0 + (up ? -40.8 : 40.8);
            previous = step;
            occupied.add((step, part.headOffsets[i]));
          }
        }
        // Accidentals whose vertical ink would touch get separate columns.
        final accidentalColumns = <List<int>>[];
        final left = group
            .map(
              (i) =>
                  part.headOffsets[i] -
                  (ScoreNotationMetrics.ledgerYs(
                        EngravingLayout.noteY(symbols[i] as Note, measures[p]!),
                      ).isEmpty
                      ? 7
                      : 11),
            )
            .reduce(math.min);
        for (final i in group.where(
          (i) => (symbols[i] as Note).alter != null,
        )) {
          final y = pitch(symbols[i] as Note);
          var col = 0;
          while (col < accidentalColumns.length &&
              accidentalColumns[col].any((v) => (v - y).abs() < 4)) {
            col++;
          }
          if (col == accidentalColumns.length) accidentalColumns.add([]);
          accidentalColumns[col].add(y);
          part.accidentalOffsets[i] =
              left - 3 - 16 * (col + 1) - part.headOffsets[i];
        }
      }
      for (final (i, s) in symbols.indexed) {
        final ink = _ink[part.keys[i]]!;
        final grace = s is Note && s.grace != null;
        final scale = grace ? 0.65 : 1.0;
        final shift = part.headOffsets[i];
        final dots = switch (s) {
          Note(:final dots) || Rest(:final dots) => dots,
          _ => 0,
        };
        final ledger =
            s is Note &&
            ScoreNotationMetrics.ledgerYs(
              EngravingLayout.noteY(s, measures[p]!),
            ).isNotEmpty;
        ink.left = math.max(ink.left, (ledger ? 11 : 7) * scale - shift);
        ink.right = math.max(
          ink.right,
          shift +
              (dots > 0
                      ? 15 + 6 * dots
                      : ledger
                      ? 11
                      : 9) *
                  scale,
        );
        if (part.accidentalOffsets[i] case final a?) {
          ink.left = math.max(ink.left, -shift - a * scale);
        }
        if (s is Note) {
          for (final l in s.lyrics.where((l) => !l.hidden)) {
            final half = EngravingLayout.textWidth(l.text) / 2;
            ink.left = math.max(ink.left, half - shift);
            ink.right = math.max(ink.right, half + shift);
          }
        }
      }
      for (final a in measures[p]?.annotations ?? const <ScoreAnnotation>[]) {
        if (a.hidden) continue;
        final ink =
            _ink[(a.offset.isNegative ? MusicalTime.zero : a.offset, 0)]!;
        ink.left = math.max(
          ink.left,
          a.kind == AnnotationKind.rehearsal ? 4 : 0,
        );
        ink.right = math.max(ink.right, EngravingLayout.textWidth(a.label) + 8);
      }
    }
    // Minimum ink distances are hard constraints. Remaining space follows
    // the duration spring (a doubled duration has 1.5x the ideal space).
    _minimum.add(_ink[columns.first]!.left + 4);
    for (var i = 1; i < columns.length; i++) {
      final before = columns[i - 1], after = columns[i];
      final grace = before.$2 < 0 && before.$1 == after.$1;
      _minimum.add(
        math.max(
          grace ? 14.0 : 10.0,
          _ink[before]!.right + _ink[after]!.left + 4,
        ),
      );
    }
    _tail = _ink[columns.last]!.right + 4;
  }
  final List<Measure?> measures;
  final staff = <StaffEngraving>[];
  final _ink = <EngravingColumn, _ColumnInk>{};
  late final List<EngravingColumn> columns;
  late final MusicalTime duration;
  final _minimum = <double>[];
  late final double _tail;
  // Conservatively include an in-measure time signature in width planning.
  double get minimumWidth =>
      34 + 16 + _minimum.fold(0.0, (a, b) => a + b) + _tail;
  static int pitch(Note n) =>
      n.octave * 7 +
      const ['C', 'D', 'E', 'F', 'G', 'A', 'B'].indexOf(n.step.toUpperCase());

  BarPlacement place({required double width, double inset = 16}) {
    final minimum = _minimum.fold(0.0, (a, b) => a + b) + _tail;
    final extra = math.max(0.0, width - inset - 16 - minimum);
    final weights = <double>[.7];
    for (var i = 1; i < columns.length; i++) {
      final a = columns[i - 1], b = columns[i];
      weights.add(
        a.$1 == b.$1
            ? 0
            : math.pow((b.$1 - a.$1).asDouble, .5849625007211562).toDouble(),
      );
    }
    final total = weights.fold(.4, (a, b) => a + b);
    var x = inset;
    final positions = <EngravingColumn, double>{};
    for (var i = 0; i < columns.length; i++) {
      x += _minimum[i] + extra * weights[i] / total;
      positions[columns[i]] = x;
    }
    return BarPlacement(this, positions, width);
  }
}

class _ColumnInk {
  double left = 0, right = 0;
}

class StaffEngraving {
  StaffEngraving(this.symbols, this.keys)
    : headOffsets = List.filled(symbols.length, 0.0),
      accidentalOffsets = List.filled(symbols.length, null),
      stemUps = List.filled(symbols.length, null),
      stemOffsets = List.filled(symbols.length, 0.0),
      stemStarts = List.filled(symbols.length, 0.0),
      stemEnds = List.filled(symbols.length, 0.0);
  final List<ScoreSymbol> symbols;
  final List<EngravingColumn> keys;
  final List<double> headOffsets;
  final List<double?> accidentalOffsets;
  final List<bool?> stemUps;
  final List<double> stemOffsets, stemStarts, stemEnds;
}

class BarPlacement {
  const BarPlacement(this.bar, this.positions, this.width);
  final BarEngraving bar;
  final Map<EngravingColumn, double> positions;
  final double width;
  double symbolX(int part, int index) {
    final staff = bar.staff[part];
    final s = staff.symbols[index];
    if (s is Rest && s.measureRest) return width / 2;
    return positions[staff.keys[index]]! + staff.headOffsets[index];
  }

  double stemX(int part, int index) =>
      positions[bar.staff[part].keys[index]]! +
      bar.staff[part].stemOffsets[index];
  double timeX(MusicalTime time) {
    final main = positions.keys.where((k) => k.$2 == 0).toList();
    if (time.compareTo(main.first.$1) <= 0) return positions[main.first]!;
    for (var i = 1; i < main.length; i++) {
      if (time.compareTo(main[i].$1) <= 0) {
        final a = main[i - 1], b = main[i];
        return positions[a]! +
            (positions[b]! - positions[a]!) *
                ((time - a.$1) / (b.$1 - a.$1)).asDouble;
      }
    }
    return positions[main.last]!;
  }
}
