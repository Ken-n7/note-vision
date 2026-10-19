// Dev tool, not part of the test suite: measures NotationChecker the way
// the paper's Objective 3 asks (issue detection accuracy >= 80%, false
// warning rate <= 20%, validation within 5 s).
//
//   NV_CHECK_DIR=/path/to/mxl/folder flutter test tool/notation_check_eval_test.dart
//
// Reads every .mxl/.xml lead sheet in the folder (e.g. OpenEWLD), keeps the
// ones the checker finds nothing wrong with as correct references, then
// plants one scan-style error at a time and checks that the checker reports
// it at the right place (found) and nothing else (no false warning).
// Prints the report and writes it to NV_CHECK_OUT (default
// <dir>/../notation_check_report.txt).
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/accidentals.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/features/musicXML/musicxml_importer.dart';
import 'package:note_vision/features/musicXML/musicxml_parser_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

typedef Planted = ({
  String name,
  Score score,
  NotationIssueKind kind,
  int part,
  Set<int> measures,
});

void main() {
  test('notation check evaluation', () {
    final dir = Platform.environment['NV_CHECK_DIR'];
    if (dir == null) return;
    final files =
        Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.mxl') || f.path.endsWith('.xml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final scores = <Score>[];
    var unreadable = 0;
    for (final f in files) {
      final score = _load(f);
      if (score == null || score.parts.isEmpty) {
        unreadable++;
      } else {
        scores.add(score);
      }
    }

    // Clean pass: what the checker says about published lead sheets.
    final cleanKinds = <String, int>{};
    final references = <Score>[];
    var cleanBars = 0;
    final checkMs = <double>[];
    for (final s in scores) {
      final watch = Stopwatch()..start();
      final issues = NotationChecker.check(s);
      checkMs.add(watch.elapsedMicroseconds / 1000);
      cleanBars += s.parts.first.measures.length;
      for (final i in issues) {
        cleanKinds[i.kind.name] = (cleanKinds[i.kind.name] ?? 0) + 1;
      }
      if (issues.isEmpty) references.add(s);
    }

    // Planted errors.
    final rng = Random(7);
    final found = <String, int>{};
    final tried = <String, int>{};
    final fixed = <String, int>{};
    final withFix = <String, int>{};
    var reported = 0;
    final falseByKind = <String, int>{};
    var falseWarnings = 0;
    for (final s in references) {
      for (final plant in _plants) {
        for (var trial = 0; trial < 3; trial++) {
          final p = plant(s, rng);
          if (p == null) continue;
          tried[p.name] = (tried[p.name] ?? 0) + 1;
          final watch = Stopwatch()..start();
          final issues = NotationChecker.check(p.score);
          checkMs.add(watch.elapsedMicroseconds / 1000);
          bool matches(NotationIssue i) =>
              i.kind == p.kind &&
              i.partIndex == p.part &&
              p.measures.contains(i.measureIndex);
          final hits = issues.where(matches).toList();
          reported += issues.length;
          falseWarnings += issues.length - hits.length;
          for (final i in issues.where((i) => !matches(i))) {
            final k = '${p.name} -> ${i.kind.name}';
            falseByKind[k] = (falseByKind[k] ?? 0) + 1;
          }
          if (hits.isEmpty) continue;
          found[p.name] = (found[p.name] ?? 0) + 1;
          final fix = hits.firstWhere(
            (i) => i.hasFix,
            orElse: () => hits.first,
          );
          if (fix.hasFix) {
            withFix[p.name] = (withFix[p.name] ?? 0) + 1;
            if (NotationChecker.check(fix.fix!(p.score)).isEmpty) {
              fixed[p.name] = (fixed[p.name] ?? 0) + 1;
            }
          }
        }
      }
    }

    final totalTried = tried.values.fold(0, (a, b) => a + b);
    final totalFound = found.values.fold(0, (a, b) => a + b);
    checkMs.sort();
    final b = StringBuffer()
      ..writeln(
        'Notation check evaluation (${DateTime.now().toIso8601String().substring(0, 10)})',
      )
      ..writeln('Source: $dir')
      ..writeln(
        'Files: ${files.length}, read: ${scores.length}, unreadable: $unreadable',
      )
      ..writeln()
      ..writeln(
        'Clean lead sheets: ${references.length} of ${scores.length} have no issue',
      )
      ..writeln(
        '  warnings on published scores per kind: $cleanKinds '
        '(over $cleanBars bars)',
      )
      ..writeln()
      ..writeln(
        'Planted errors on the ${references.length} clean scores '
        '(3 per error type per score):',
      )
      ..writeln('  ${'error'.padRight(34)} planted  found   rate  fix ok');
    for (final name in tried.keys) {
      final t = tried[name]!;
      final f = found[name] ?? 0;
      final wf = withFix[name] ?? 0;
      b.writeln(
        '  ${name.padRight(34)} ${'$t'.padLeft(7)} ${'$f'.padLeft(6)} '
        '${(f / t * 100).toStringAsFixed(1).padLeft(5)}%  '
        '${wf == 0 ? '-' : '${fixed[name] ?? 0}/$wf'}',
      );
    }
    b
      ..writeln()
      ..writeln(
        'Issue detection accuracy: $totalFound / $totalTried = '
        '${(totalFound / totalTried * 100).toStringAsFixed(1)}% (target >= 80%)',
      )
      ..writeln(
        'False warning rate: $falseWarnings / $reported = '
        '${(falseWarnings / reported * 100).toStringAsFixed(1)}% (target <= 20%)',
      )
      ..writeln('  false warnings by planted error -> kind: $falseByKind')
      ..writeln(
        'Validation time per score: median '
        '${checkMs[checkMs.length ~/ 2].toStringAsFixed(2)} ms, max '
        '${checkMs.last.toStringAsFixed(2)} ms on this computer (target <= 5 s)',
      );
    final report = b.toString();
    // ignore: avoid_print
    print(report);
    File(
      Platform.environment['NV_CHECK_OUT'] ??
          '${Directory(dir).parent.path}/notation_check_report.txt',
    ).writeAsStringSync(report);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Score? _load(File f) {
  try {
    final bytes = f.readAsBytesSync();
    String text;
    if (f.path.endsWith('.mxl')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.firstWhere(
        (e) =>
            e.isFile &&
            !e.name.startsWith('META-INF') &&
            (e.name.endsWith('.xml') || e.name.endsWith('.musicxml')),
      );
      text = MusicXmlImporter.decodeXmlText(entry.content as List<int>);
    } else {
      text = MusicXmlImporter.decodeXmlText(bytes);
    }
    final parsed = MusicXmlParserService().parse(text);
    if (!parsed.success || parsed.document == null) return null;
    return const MusicXmlScoreConverter().convert(parsed.document!);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Planted errors: each one is a mistake the scanner can make.
// ---------------------------------------------------------------------------

typedef _Plant = Planted? Function(Score s, Random rng);

final List<_Plant> _plants = [
  _missedSymbol,
  _doubleDetection,
  _misreadValue,
  _missedBarline,
  _barlineEarly,
  _redundantAccidental,
  _wrongTimeSignature,
  _missedClef,
  _missedBeamPartner,
  _unsureDetection,
];

/// (part, measure) pairs whose measure has at least [minMusical] notes/rests,
/// leaving out the first and last bar (pickup and ending may be short).
List<(int, int)> _bars(Score s, {int minMusical = 1}) => [
  for (var p = 0; p < s.parts.length; p++)
    for (var m = 1; m < s.parts[p].measures.length - 1; m++)
      if (_musicalIdx(s.parts[p].measures[m]).length >= minMusical) (p, m),
];

List<int> _musicalIdx(Measure m) => [
  for (var i = 0; i < m.symbols.length; i++)
    if ((m.symbols[i] is Note && !(m.symbols[i] as Note).isChordTone) ||
        m.symbols[i] is Rest)
      i,
];

T _pick<T>(List<T> xs, Random rng) => xs[rng.nextInt(xs.length)];

Planted? _missedSymbol(Score s, Random rng) {
  final bars = _bars(s, minMusical: 2);
  if (bars.isEmpty) return null;
  final (p, m) = _pick(bars, rng);
  final musical = _musicalIdx(s.parts[p].measures[m]);
  final i = _pick(musical, rng);
  // Drop the note with its chord tones.
  var score = s;
  final syms = s.parts[p].measures[m].symbols;
  var end = i + 1;
  while (end < syms.length &&
      syms[end] is Note &&
      (syms[end] as Note).isChordTone) {
    end++;
  }
  for (var k = end - 1; k >= i; k--) {
    score = score.deleteSymbolAt(p, m, k);
  }
  return (
    name: 'missed note or rest',
    score: score,
    kind: NotationIssueKind.beatTotal,
    part: p,
    measures: {m},
  );
}

Planted? _doubleDetection(Score s, Random rng) {
  final bars = _bars(s);
  if (bars.isEmpty) return null;
  final (p, m) = _pick(bars, rng);
  final i = _pick(_musicalIdx(s.parts[p].measures[m]), rng);
  final sym = s.parts[p].measures[m].symbols[i];
  return (
    name: 'note or rest detected twice',
    score: s.insertSymbolAt(p, m, i + 1, sym),
    kind: NotationIssueKind.beatTotal,
    part: p,
    measures: {m},
  );
}

const _longer = {
  'sixteenth': 'eighth',
  '16th': 'eighth',
  'eighth': 'quarter',
  'quarter': 'half',
  'half': 'whole',
};

Planted? _misreadValue(Score s, Random rng) {
  final bars = _bars(s);
  if (bars.isEmpty) return null;
  final (p, m) = _pick(bars, rng);
  final measure = s.parts[p].measures[m];
  final candidates = [
    for (final i in _musicalIdx(measure))
      if (_longer.containsKey(_typeOf(measure.symbols[i]))) i,
  ];
  if (candidates.isEmpty) return null;
  final i = _pick(candidates, rng);
  final old = measure.symbols[i];
  final type = _longer[_typeOf(old)]!;
  final changed = switch (old) {
    Note() => _note(old, type: type, beamed: false),
    Rest() => Rest(duration: old.duration * 2, type: type, dots: old.dots),
    _ => old,
  };
  return (
    name: 'value read too long',
    score: s.replaceSymbolAt(p, m, i, changed),
    kind: NotationIssueKind.beatTotal,
    part: p,
    measures: {m},
  );
}

Planted? _missedBarline(Score s, Random rng) {
  final bars = _bars(s);
  final usable = [
    for (final (p, m) in bars)
      if (m + 1 < s.parts[p].measures.length - 1 &&
          s.parts[p].measures[m + 1].timeSignature == null &&
          s.parts[p].measures[m + 1].keySignature == null &&
          s.parts[p].measures[m + 1].clef == null &&
          _musicalIdx(s.parts[p].measures[m + 1]).isNotEmpty)
        (p, m),
  ];
  if (usable.isEmpty) return null;
  final (p, m) = _pick(usable, rng);
  final part = s.parts[p];
  final merged = Measure(
    number: part.measures[m].number,
    clef: part.measures[m].clef,
    timeSignature: part.measures[m].timeSignature,
    keySignature: part.measures[m].keySignature,
    symbols: [...part.measures[m].symbols, ...part.measures[m + 1].symbols],
  );
  final measures = [...part.measures]
    ..[m] = merged
    ..removeAt(m + 1)
    ..add(const Measure(number: 0, symbols: [])); // keep parts equally long
  return (
    name: 'missed barline (bars merged)',
    score: _setPart(s, p, measures),
    kind: NotationIssueKind.beatTotal,
    part: p,
    measures: {m},
  );
}

Planted? _barlineEarly(Score s, Random rng) {
  final bars = [
    for (final (p, m) in _bars(s, minMusical: 2))
      if (m + 1 < s.parts[p].measures.length) (p, m),
  ];
  if (bars.isEmpty) return null;
  final (p, m) = _pick(bars, rng);
  final from = s.parts[p].measures[m].symbols;
  final last = _musicalIdx(s.parts[p].measures[m]).last;
  final moved = from.sublist(last);
  var score = s;
  for (var k = from.length - 1; k >= last; k--) {
    score = score.deleteSymbolAt(p, m, k);
  }
  for (var k = moved.length - 1; k >= 0; k--) {
    score = score.insertSymbolAt(p, m + 1, 0, moved[k]);
  }
  return (
    name: 'barline read one note early',
    score: score,
    kind: NotationIssueKind.beatTotal,
    part: p,
    measures: {m, m + 1},
  );
}

Planted? _redundantAccidental(Score s, Random rng) {
  final options = <(int, int, int, int)>[];
  for (var p = 0; p < s.parts.length; p++) {
    final state = Accidentals();
    final seen = <String>{};
    for (var m = 0; m < s.parts[p].measures.length; m++) {
      final measure = s.parts[p].measures[m];
      state.startMeasure(measure);
      final prevSeen = seen.toSet();
      seen.clear();
      for (var i = 0; i < measure.symbols.length; i++) {
        final n = measure.symbols[i];
        if (n is! Note) continue;
        final pitch = '${n.step}${n.octave}';
        final sounding = state.sounding(n);
        if (n.alter == null &&
            !seen.contains(pitch) &&
            !prevSeen.contains(pitch)) {
          options.add((p, m, i, sounding));
        }
        if (n.alter != null) seen.add(pitch);
      }
    }
  }
  if (options.isEmpty) return null;
  final (p, m, i, alter) = _pick(options, rng);
  final n = s.parts[p].measures[m].symbols[i] as Note;
  return (
    name: 'accidental that changes nothing',
    score: s.replaceSymbolAt(p, m, i, _note(n, alter: alter)),
    kind: NotationIssueKind.misplacedAccidental,
    part: p,
    measures: {m},
  );
}

Planted? _wrongTimeSignature(Score s, Random rng) {
  final written = s.parts.first.measures.first.timeSignature;
  if (written == null) return null;
  final others =
      [
            const TimeSignature(beats: 2, beatType: 4),
            const TimeSignature(beats: 3, beatType: 4),
            const TimeSignature(beats: 4, beatType: 4),
          ]
          .where(
            (t) =>
                t.beats * 4 / t.beatType !=
                written.beats * 4 / written.beatType,
          )
          .toList();
  if (others.isEmpty) return null;
  final wrong = _pick(others, rng);
  return (
    name: 'time signature misread',
    score: s.setTimeSignatureAt(0, wrong),
    kind: NotationIssueKind.timeSignature,
    part: 0,
    measures: {0},
  );
}

Planted? _missedClef(Score s, Random rng) {
  final p = rng.nextInt(s.parts.length);
  final measures = [
    for (final m in s.parts[p].measures)
      Measure(
        number: m.number,
        timeSignature: m.timeSignature,
        keySignature: m.keySignature,
        symbols: [
          for (final x in m.symbols)
            if (x is! Clef) x,
        ],
      ),
  ];
  return (
    name: 'clef missed',
    score: _setPart(s, p, measures),
    kind: NotationIssueKind.missingComponent,
    part: p,
    measures: {0},
  );
}

Planted? _missedBeamPartner(Score s, Random rng) {
  final options = <(int, int, int)>[];
  for (final (p, m) in _bars(s)) {
    final syms = s.parts[p].measures[m].symbols;
    final idx = _musicalIdx(s.parts[p].measures[m]);
    for (var k = 0; k < idx.length; k++) {
      final n = syms[idx[k]];
      if (n is! Note || n.beamed || n.type != 'eighth') continue;
      bool beamedAt(int j) =>
          j >= 0 &&
          j < idx.length &&
          syms[idx[j]] is Note &&
          (syms[idx[j]] as Note).beamed;
      if (!beamedAt(k - 1) && !beamedAt(k + 1)) options.add((p, m, idx[k]));
    }
  }
  if (options.isEmpty) return null;
  final (p, m, i) = _pick(options, rng);
  final n = s.parts[p].measures[m].symbols[i] as Note;
  return (
    name: 'beam partner missed',
    score: s.replaceSymbolAt(p, m, i, _note(n, beamed: true)),
    kind: NotationIssueKind.missingComponent,
    part: p,
    measures: {m},
  );
}

Planted? _unsureDetection(Score s, Random rng) {
  final bars = _bars(s);
  if (bars.isEmpty) return null;
  final (p, m) = _pick(bars, rng);
  final i = _pick(_musicalIdx(s.parts[p].measures[m]), rng);
  final old = s.parts[p].measures[m].symbols[i];
  final conf = 0.4 + rng.nextDouble() * 0.19;
  final changed = switch (old) {
    Note() => _note(old, confidence: conf),
    Rest() => Rest(
      duration: old.duration,
      type: old.type,
      dots: old.dots,
      confidence: conf,
    ),
    _ => old,
  };
  return (
    name: 'low-confidence detection',
    score: s.replaceSymbolAt(p, m, i, changed),
    kind: NotationIssueKind.lowConfidence,
    part: p,
    measures: {m},
  );
}

String? _typeOf(ScoreSymbol s) => switch (s) {
  Note(:final type) => type,
  Rest(:final type) => type,
  _ => null,
};

const Object _keep = Object();

Note _note(
  Note n, {
  String? type,
  bool? beamed,
  Object? alter = _keep,
  double? confidence,
}) => Note(
  step: n.step,
  octave: n.octave,
  alter: identical(alter, _keep) ? n.alter : alter as int?,
  duration: type == null ? n.duration : n.duration * 2,
  type: type ?? n.type,
  voice: n.voice,
  staff: n.staff,
  beamed: beamed ?? n.beamed,
  dots: n.dots,
  isChordTone: n.isChordTone,
  confidence: confidence ?? n.confidence,
);

Score _setPart(Score s, int p, List<Measure> measures) {
  final parts = [...s.parts];
  parts[p] = Part(
    id: s.parts[p].id,
    name: s.parts[p].name,
    measures: [
      for (var i = 0; i < measures.length; i++)
        Measure(
          number: i + 1,
          clef: measures[i].clef,
          timeSignature: measures[i].timeSignature,
          keySignature: measures[i].keySignature,
          symbols: measures[i].symbols,
          startsNewPage: measures[i].startsNewPage,
          startsNewSystem: measures[i].startsNewSystem,
          leftBarlineType: measures[i].leftBarlineType,
          rightBarlineType: measures[i].rightBarlineType,
        ),
    ],
  );
  return Score(id: s.id, title: s.title, composer: s.composer, parts: parts);
}
