import 'dart:convert';

import '../models/measure.dart';
import '../models/note.dart';
import '../models/part.dart';
import '../models/rest.dart';
import '../models/score.dart';
import '../models/score_symbol.dart';
import 'accidentals.dart';

/// Keeps each linked staff ([Part.linked]) showing the same music as the
/// staff above it: whichever of the two [next] changed from [prev] is copied
/// to the other (the upper one when both did, or when [prev] has no such
/// pair). Each staff keeps its own clefs and its symbols' review IDs, staff
/// and voice numbers, so retained MusicXML bindings still find them.
/// Returns [next] itself when nothing changes.
Score syncLinkedStaves(Score next, Score? prev) {
  if (!next.parts.any((p) => p.linked)) return next;
  final before = {for (final p in prev?.parts ?? const <Part>[]) p.id: p};
  final parts = [...next.parts];
  var changed = false;
  for (var i = 1; i < parts.length; i++) {
    final lower = parts[i];
    if (!lower.linked || !lower.joinsPrevious) continue;
    final upper = parts[i - 1];
    bool edited(Part p) =>
        !identical(before[p.id]?.measures, p.measures) &&
        _content(before[p.id]?.measures) != _content(p.measures);
    final fromLower = edited(lower) && !edited(upper) && before.isNotEmpty;
    final source = fromLower ? lower : upper;
    final target = fromLower ? upper : lower;
    final copied = _copy(source, target);
    if (_content(copied.measures) == _content(target.measures)) continue;
    parts[fromLower ? i - 1 : i] = copied;
    changed = true;
  }
  return changed ? next.copyWith(parts: parts) : next;
}

/// The music of [measures], without the per-staff clef and IDs.
String _content(List<Measure>? measures) => jsonEncode([
  for (final m in measures ?? const <Measure>[])
    (m.toJson()
        ..remove('clef')
        ..remove('reviewId')
        ..remove('source'))
      ..['symbols'] = [
        for (final s in m.symbols)
          s.toJson()
            ..remove('reviewId')
            ..remove('source')
            ..remove('voice')
            ..remove('staff'),
      ],
]);

Part _copy(Part source, Part target) {
  final shift = 4 * (target.staff - source.staff);
  ScoreSymbol place(ScoreSymbol s, ScoreSymbol? old) => switch (s) {
    Note() => s.copyWith(
      reviewId: old is Note ? old.reviewId : null,
      source: null,
      voice: s.voice == null ? null : (s.voice! + shift).clamp(1, 16),
      staff: s.staff == null ? null : target.staff,
    ),
    Rest() => s.copyWith(
      reviewId: old is Rest ? old.reviewId : null,
      source: null,
      voice: s.voice == null ? null : (s.voice! + shift).clamp(1, 16),
      staff: s.staff == null ? null : target.staff,
    ),
    _ => s,
  };
  return target.copyWith(
    measures: [
      for (final (i, m) in source.measures.indexed)
        () {
          final own = i < target.measures.length ? target.measures[i] : null;
          return m.copyWith(
            clef: i == 0
                ? own?.clef ?? target.measures.firstOrNull?.clef
                : own?.clef,
            reviewId: own?.reviewId,
            source: own?.source,
            symbols: [
              for (final (k, s) in m.symbols.indexed)
                place(
                  s,
                  own != null && k < own.symbols.length ? own.symbols[k] : null,
                ),
            ],
          );
        }(),
    ],
  );
}

/// [parts] with each TAB staff that repeats the notation staff above it, in
/// the same instrument, marked [Part.linked]: MuseScore writes a linked
/// staff's notes again on it.
List<Part> linkRepeatedTabStaves(List<Part> parts) => [
  for (final (i, p) in parts.indexed)
    p.copyWith(
      linked:
          i > 0 &&
          p.joinsPrevious &&
          p.isTab &&
          !parts[i - 1].isTab &&
          _heard(p) == _heard(parts[i - 1]),
    ),
];

/// Each bar's rhythm and sounding pitches.
String _heard(Part part) {
  final accidentals = Accidentals();
  return [
    for (final m in part.measures)
      () {
        accidentals.startMeasure(m);
        return [
          for (final s in m.symbols)
            switch (s) {
              Note() =>
                'n${s.step}${s.octave}${accidentals.sounding(s)}'
                    '${s.type}${s.dots}${s.isChordTone}${s.grace}',
              Rest() => 'r${s.type}${s.dots}',
              _ => '',
            },
        ].join(' ');
      }(),
  ].join('|');
}
