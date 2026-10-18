import 'note.dart';
import 'note_value.dart';
import 'rest.dart';
import 'score_symbol.dart';
import 'time_signature.dart';

/// Shared beam semantics for editing, drawing, checking, and MusicXML export.
/// Old scores with only `beamed: true` retain their consecutive-note groups.
abstract final class BeamGrouping {
  static int levels(Note note) => switch (note.type.trim().toLowerCase()) {
    'eighth' => 1,
    'sixteenth' || '16th' => 2,
    _ => 0,
  };

  static bool eligible(ScoreSymbol symbol) =>
      symbol is Note && !symbol.isChordTone && levels(symbol) > 0;

  static (int, int) _voice(Note note) => (note.voice ?? 1, note.staff ?? 1);

  static List<List<int>> groups(
    List<ScoreSymbol> symbols, {
    int level = 1,
    List<int>? within,
  }) {
    final result = <List<int>>[];
    var current = <int>[];
    void finish() {
      if (current.isNotEmpty) result.add(current);
      current = [];
    }

    for (final index in within ?? List.generate(symbols.length, (i) => i)) {
      final symbol = symbols[index];
      if (symbol is Note && symbol.isChordTone) continue;
      if (!eligible(symbol) ||
          !(symbol as Note).beamed ||
          levels(symbol) < level) {
        finish();
        continue;
      }
      final mark = symbol.beams[level];
      if (current.isNotEmpty &&
          (mark == BeamValue.begin ||
              mark == BeamValue.forwardHook ||
              mark == BeamValue.backwardHook ||
              _voice(symbols[current.last] as Note) != _voice(symbol))) {
        finish();
      }
      current.add(index);
      if (mark == BeamValue.end ||
          mark == BeamValue.forwardHook ||
          mark == BeamValue.backwardHook) {
        finish();
      }
    }
    finish();
    return result;
  }

  static List<int> groupAt(List<ScoreSymbol> symbols, int index) =>
      groups(symbols).where((group) => group.contains(index)).firstOrNull ??
      const [];

  /// Repair explicit groups after notes are removed, inserted, or changed
  /// to a different value. Detector-only orphan flags remain reviewable.
  static List<ScoreSymbol> repairExplicit(List<ScoreSymbol> symbols) {
    List<ScoreSymbol>? result;
    for (final group in groups(symbols)) {
      if (!group.any((i) => (symbols[i] as Note).beams.isNotEmpty)) continue;
      for (final i in group) {
        final old = symbols[i] as Note;
        final marks = valuesFor(symbols, i);
        if (old.beamed == marks.isNotEmpty &&
            old.beams.length == marks.length &&
            marks.entries.every(
              (entry) => old.beams[entry.key] == entry.value,
            )) {
          continue;
        }
        (result ??= List.of(symbols))[i] = old.withBeams(marks);
      }
    }
    return result ?? symbols;
  }

  static BeamValue _mark(List<int> group, int index) => index == group.first
      ? BeamValue.begin
      : index == group.last
      ? BeamValue.end
      : BeamValue.continueBeam;

  /// Complete beam values, including the secondary beam and isolated hooks.
  /// A single note has a flag and exports no open beam.
  static Map<int, BeamValue> valuesFor(List<ScoreSymbol> symbols, int index) {
    final primary = groupAt(symbols, index);
    if (primary.length < 2) return const {};
    final result = <int, BeamValue>{1: _mark(primary, index)};
    final note = symbols[index] as Note;
    for (var level = 2; level <= levels(note); level++) {
      final secondary = groups(
        symbols,
        level: level,
        within: primary,
      ).where((group) => group.contains(index)).firstOrNull;
      if (secondary == null) continue;
      if (secondary.length > 1) {
        result[level] = _mark(secondary, index);
      } else {
        final mark = note.beams[level];
        result[level] =
            mark == BeamValue.forwardHook || mark == BeamValue.backwardHook
            ? mark!
            : index == primary.first
            ? BeamValue.forwardHook
            : BeamValue.backwardHook;
      }
    }
    return result;
  }

  static bool canJoin(List<ScoreSymbol> symbols, int start, int end) {
    if (start < 0 ||
        end >= symbols.length ||
        start >= end ||
        !eligible(symbols[start]) ||
        !eligible(symbols[end])) {
      return false;
    }
    final voice = _voice(symbols[start] as Note);
    var count = 0;
    for (var i = start; i <= end; i++) {
      final symbol = symbols[i];
      if (symbol is Note && symbol.isChordTone) continue;
      if (!eligible(symbol) || _voice(symbol as Note) != voice) return false;
      count++;
    }
    return count >= 2;
  }

  static List<ScoreSymbol> join(List<ScoreSymbol> symbols, int start, int end) {
    if (!canJoin(symbols, start, end)) return symbols;
    return _range(symbols, start, end, join: true);
  }

  static List<ScoreSymbol> separate(
    List<ScoreSymbol> symbols,
    int start,
    int end,
  ) {
    if (start < 0 || end >= symbols.length || start > end) return symbols;
    return _range(symbols, start, end, join: false);
  }

  static List<ScoreSymbol> _range(
    List<ScoreSymbol> symbols,
    int start,
    int end, {
    required bool join,
  }) {
    final affected = <int>{
      for (var i = start; i <= end; i++)
        if (eligible(symbols[i])) i,
    };
    final replacement = <List<int>>[];
    for (final group in groups(symbols)) {
      if (!group.any(affected.contains)) continue;
      affected.addAll(group);
      replacement.add(group.where((i) => i < start).toList());
      replacement.add(group.where((i) => i > end).toList());
    }
    if (join) {
      replacement.add([
        for (var i = start; i <= end; i++)
          if (eligible(symbols[i])) i,
      ]);
    }
    return _write(symbols, affected, replacement);
  }

  static List<ScoreSymbol> split(
    List<ScoreSymbol> symbols,
    int index, {
    required bool before,
  }) {
    final group = groupAt(symbols, index);
    final cut = group.indexOf(index) + (before ? 0 : 1);
    if (cut <= 0 || cut >= group.length) return symbols;
    return _write(symbols, group.toSet(), [
      group.sublist(0, cut),
      group.sublist(cut),
    ]);
  }

  static List<ScoreSymbol> byBeat(
    List<ScoreSymbol> symbols,
    TimeSignature time, {
    bool pickup = false,
  }) {
    if (!canGroupByBeat(time)) return symbols;
    final compound =
        (time.beats > 3 && time.beats % 3 == 0) ||
        (time.beats == 3 && time.beatType >= 8);
    final beat = 4.0 / time.beatType * (compound ? 3 : 1);
    final clocks = <(int, int), double>{};
    if (pickup) {
      final capacity = time.beats * 4.0 / time.beatType;
      for (final entry in _voiceLengths(symbols).entries) {
        if (entry.value < capacity) clocks[entry.key] = capacity - entry.value;
      }
    }
    final replacement = <List<int>>[];
    var current = <int>[];
    (int, int)? previousVoice;
    int? previousBeat;
    void finish() {
      if (current.isNotEmpty) replacement.add(current);
      current = [];
    }

    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      if (symbol is Note && symbol.isChordTone) continue;
      final (type, dots, duration, voice, staff) = switch (symbol) {
        Note(
          :final type,
          :final dots,
          :final duration,
          :final voice,
          :final staff,
        ) ||
        Rest(
          :final type,
          :final dots,
          :final duration,
          :final voice,
          :final staff,
        ) => (type, dots, duration, voice ?? 1, staff ?? 1),
        _ => ('', 0, 0, 1, 1),
      };
      if (type.isEmpty) {
        finish();
        continue;
      }
      final key = (voice, staff);
      final onset = clocks[key] ?? 0;
      final length = quarterLength(type, dots, duration);
      final bucket = ((onset + 1e-7) / beat).floor();
      clocks[key] = onset + length;
      if (!eligible(symbol) || onset + length > (bucket + 1) * beat + 1e-7) {
        finish();
        continue;
      }
      if (key != previousVoice || bucket != previousBeat) finish();
      current.add(i);
      previousVoice = key;
      previousBeat = bucket;
    }
    finish();
    return _write(symbols, {
      for (var i = 0; i < symbols.length; i++)
        if (eligible(symbols[i])) i,
    }, replacement);
  }

  /// Additive meters need an explicit accent pattern (for example 3+2).
  /// Keep their existing notation until a range is selected manually.
  static bool canGroupByBeat(TimeSignature time) =>
      time.beats > 0 &&
      time.beatType > 0 &&
      (time.beatType < 8 || time.beats <= 4 || time.beats % 3 == 0);

  static Map<(int, int), double> _voiceLengths(List<ScoreSymbol> symbols) {
    final result = <(int, int), double>{};
    for (final symbol in symbols) {
      if (symbol is Note && !symbol.isChordTone) {
        final key = _voice(symbol);
        result[key] =
            (result[key] ?? 0) +
            quarterLength(symbol.type, symbol.dots, symbol.duration);
      } else if (symbol is Rest) {
        final key = (symbol.voice ?? 1, symbol.staff ?? 1);
        result[key] =
            (result[key] ?? 0) +
            quarterLength(symbol.type, symbol.dots, symbol.duration);
      }
    }
    return result;
  }

  static double quarters(List<ScoreSymbol> symbols) =>
      _voiceLengths(symbols).values.fold(0.0, (a, b) => a > b ? a : b);

  static List<ScoreSymbol> _write(
    List<ScoreSymbol> symbols,
    Set<int> affected,
    List<List<int>> replacement,
  ) {
    final next = List<ScoreSymbol>.of(symbols);
    for (final i in affected) {
      next[i] = (symbols[i] as Note).withBeams(const {});
    }
    for (final group in replacement.where((group) => group.length >= 2)) {
      for (final i in group) {
        next[i] = (next[i] as Note).withBeams({1: _mark(group, i)});
      }
    }
    final complete = {for (final i in affected) i: valuesFor(next, i)};
    for (final i in affected) {
      final old = symbols[i] as Note;
      final marks = complete[i]!;
      next[i] =
          old.beamed == marks.isNotEmpty &&
              old.beams.length == marks.length &&
              marks.entries.every(
                (entry) => old.beams[entry.key] == entry.value,
              )
          ? old
          : old.withBeams(marks);
    }
    return List.generate(
          symbols.length,
          (i) => identical(next[i], symbols[i]),
        ).every((same) => same)
        ? symbols
        : next;
  }
}
