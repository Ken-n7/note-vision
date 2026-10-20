// Dev tool, not part of the test suite: runs real photos through the app's
// scan pipeline, then the notation checker with every suggested fix
// accepted, and measures whether the fixes bring the score closer to the
// page.
//
// Photos are shrunk as the app's image picker does (at most 1200 px).
// The page's "truth" is the hand-labelled boxes run through the same
// pipeline (a perfect detector), so detection is the only difference.
//
//   1. NV_SCAN_DIR=<yolo dir with images/ labels/> NV_SCAN_WORK=<dir> \
//      NV_SCAN_PHASE=inputs flutter test tool/real_scan_review_eval_test.dart
//      writes <work>/inputs/<page>.png, the exact 960x960 model input.
//   2. Run the model on them (scripts/run_raw.py in the data project) to
//      write <work>/raw/<page>.bin, the float32 [28][18900] output.
//   3. The same command with NV_SCAN_PHASE=eval writes <work>/report.txt,
//      <work>/pages.json and <work>/scores/<page>.{truth,scan,fixed}.json.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/basic_image_preprocessor.dart';
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';

const _anchors = 18900;
const _rows = 28;

void main() {
  test('real scan review evaluation', timeout: Timeout.none, () async {
    final dir = Platform.environment['NV_SCAN_DIR'];
    final work = Platform.environment['NV_SCAN_WORK'];
    final phase = Platform.environment['NV_SCAN_PHASE'] ?? 'eval';
    if (dir == null || work == null) return;

    final images =
        Directory('$dir/images').listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final preprocessor = BasicImagePreprocessor();

    if (phase == 'inputs') {
      Directory('$work/inputs').createSync(recursive: true);
      for (final file in images) {
        final pre = await preprocessor.preprocess(_asPicked(file));
        final input = TfliteSymbolDetector.modelInput(
          img.decodeImage(pre.bytes)!,
        );
        File(
          '$work/inputs/${_stem(file)}.png',
        ).writeAsBytesSync(img.encodePng(img.grayscale(input)));
      }
      return;
    }

    final detector = TfliteSymbolDetector();
    const mapper = DetectionToScoreMapperService();
    const staffDetector = HorizontalProjectionStaffDetector();
    Directory('$work/scores').createSync(recursive: true);

    final pages = <Map<String, Object?>>[];
    final totals = _Totals();
    for (final file in images) {
      final stem = _stem(file);
      final pre = await preprocessor.preprocess(_asPicked(file));
      final full = img.decodeImage(pre.bytes)!;
      final staves = staffDetector.detect(pre.bytes);

      Score build(Float32List raw) =>
          mapper.map(detector.detectFromOutput(full, staves, raw)).score;

      final truth = build(_labelsAsOutput(File('$dir/labels/$stem.txt')));
      final scan = build(
        File('$work/raw/$stem.bin').readAsBytesSync().buffer.asFloat32List(),
      );
      final fixed = _acceptAll(scan, truth);

      final page = _comparePage(stem, truth, scan, fixed);
      pages.add(page.json);
      totals.add(page);
      for (final (name, score) in [
        ('truth', truth),
        ('scan', scan),
        ('fixed', fixed.score),
      ]) {
        File(
          '$work/scores/$stem.$name.json',
        ).writeAsStringSync(jsonEncode(score.toJson()));
      }
    }

    File(
      '$work/pages.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(pages));
    final report = totals.report(pages.length);
    File('$work/report.txt').writeAsStringSync(report);
    // ignore: avoid_print
    print(report);
  });
}

/// The photo as the app receives it: ImagePickerHelper asks image_picker
/// for at most 1200x1200 at JPEG quality 82.
Uint8List _asPicked(File f) {
  final photo = img.bakeOrientation(img.decodeImage(f.readAsBytesSync())!);
  final scale = min(1, 1200 / max(photo.width, photo.height));
  final picked = scale < 1
      ? img.copyResize(
          photo,
          width: (photo.width * scale).round(),
          height: (photo.height * scale).round(),
          interpolation: img.Interpolation.linear,
        )
      : photo;
  return img.encodeJpg(picked, quality: 82);
}

/// The fix's label without its numbers and note names, to group alike fixes.
String _fixKind(String label) => label
    .replaceAll(RegExp(r'\d+/\d+'), 'meter')
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(
      RegExp(r'(whole|half|quarter|eighth|sixteenth) (note|rest)'),
      'value',
    )
    .replaceAll(RegExp(r'to an? (dotted )?\w+$'), 'to a shorter value');

String _stem(File f) {
  final name = f.uri.pathSegments.last;
  return name.substring(0, name.lastIndexOf('.'));
}

/// The labelled boxes as a model output: one anchor per box, sure of its
/// class. Labels are normalised to the photo, as the model's boxes are to
/// the stretched input.
Float32List _labelsAsOutput(File labels) {
  final raw = Float32List(_rows * _anchors);
  var a = 0;
  for (final line in labels.readAsLinesSync()) {
    final p = line.trim().split(RegExp(r'\s+'));
    if (p.length < 5 || a >= _anchors) continue;
    final cls = int.parse(p[0]);
    for (var k = 0; k < 4; k++) {
      raw[k * _anchors + a] = double.parse(p[k + 1]);
    }
    raw[(4 + cls) * _anchors + a] = 1;
    a++;
  }
  return raw;
}

typedef _Fixed = ({
  Score score,
  List<String> applied,
  List<List<int>> deltas,
  int rounds,
});

/// Accepts every suggested fix, one at a time, re-checking after each (as a
/// user pressing Accept down the list would). A fix that leaves the score
/// unchanged is skipped so the loop always ends.
_Fixed _acceptAll(Score score, Score truth) {
  final applied = <String>[];
  final deltas = <List<int>>[];
  final skipped = <String>{};
  var current = score;
  var rounds = 0;
  while (rounds < 300) {
    rounds++;
    final next = NotationChecker.check(
      current,
    ).where((i) => i.hasFix && !skipped.contains(i.key)).firstOrNull;
    if (next == null) break;
    final after = next.fix!(current);
    if (jsonEncode(after.toJson()) == jsonEncode(current.toJson())) {
      skipped.add(next.key);
      continue;
    }
    applied.add(_fixKind(next.fixLabel!));
    deltas.add([
      _distance(after, truth) - _distance(current, truth),
      _distance(after, truth, rhythm: true) -
          _distance(current, truth, rhythm: true),
    ]);
    current = after;
  }
  return (score: current, applied: applied, deltas: deltas, rounds: rounds);
}

/// One token per note or rest, in reading order: pitch (without its
/// written accidental, which a redundant-accidental fix may drop without
/// changing the sound) and length in quarters. [rhythm] leaves out pitch.
List<String> _tokens(List<Measure> measures, {bool rhythm = false}) => [
  for (final m in measures)
    for (final s in m.symbols)
      if (s is Note)
        '${rhythm ? 'N' : 'N${s.step}${s.octave}'}:'
            '${quarterLength(s.type, s.dots, s.duration)}'
      else if (s is Rest)
        'R:${quarterLength(s.type, s.dots, s.duration)}',
];

/// Edit distance from [score] to [truth] over the staves both have.
int _distance(Score score, Score truth, {bool rhythm = false}) {
  var d = 0;
  for (var p = 0; p < min(truth.parts.length, score.parts.length); p++) {
    d += _editDistance(
      _tokens(score.parts[p].measures, rhythm: rhythm),
      _tokens(truth.parts[p].measures, rhythm: rhythm),
    );
  }
  return d;
}

int _editDistance(List<String> a, List<String> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = min(
        min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Bars whose notes and rests fill the time signature exactly, over bars
/// with any (the first and last filled bar of a staff are left out: pickups
/// and endings may be short).
(int, int) _fullBars(Score score) {
  var full = 0, counted = 0;
  for (final part in score.parts) {
    TimeSignature? meter;
    final filled = [
      for (var m = 0; m < part.measures.length; m++)
        if (part.measures[m].symbols.any((s) => s is Note || s is Rest)) m,
    ];
    for (var m = 0; m < part.measures.length; m++) {
      final measure = part.measures[m];
      meter = measure.timeSignature ?? meter;
      if (!filled.contains(m) || m == filled.first || m == filled.last) {
        continue;
      }
      if (meter == null) continue;
      counted++;
      var total = 0.0;
      for (final s in measure.symbols) {
        if (s is Note && !s.isChordTone) {
          total += quarterLength(s.type, s.dots, s.duration);
        } else if (s is Rest) {
          total += quarterLength(s.type, s.dots, s.duration);
        }
      }
      if ((total - meter.beats * 4 / meter.beatType).abs() < 1e-6) full++;
    }
  }
  return (full, counted);
}

class _Page {
  _Page(this.json);
  final Map<String, Object?> json;
}

_Page _comparePage(String stem, Score truth, Score scan, _Fixed fixed) {
  var refTokens = 0;
  for (var p = 0; p < min(truth.parts.length, scan.parts.length); p++) {
    refTokens += _tokens(truth.parts[p].measures).length;
  }
  Map<String, int> kinds(Score s) {
    final out = <String, int>{};
    for (final i in NotationChecker.check(s)) {
      out[i.kind.name] = (out[i.kind.name] ?? 0) + 1;
    }
    return out;
  }

  final scanIssues = NotationChecker.check(scan);
  return _Page({
    'page': stem,
    'staves': {'truth': truth.parts.length, 'scan': scan.parts.length},
    'tokens': refTokens,
    'errors': {
      'scan': _distance(scan, truth),
      'fixed': _distance(fixed.score, truth),
      'scanRhythm': _distance(scan, truth, rhythm: true),
      'fixedRhythm': _distance(fixed.score, truth, rhythm: true),
    },
    'fullBars': {
      'truth': _fullBars(truth).toList(),
      'scan': _fullBars(scan).toList(),
      'fixed': _fullBars(fixed.score).toList(),
    },
    'issues': {
      'truth': kinds(truth),
      'scan': kinds(scan),
      'scanWithFix': scanIssues.where((i) => i.hasFix).length,
      'fixed': kinds(fixed.score),
    },
    'applied': fixed.applied,
    'deltas': fixed.deltas,
  });
}

extension on (int, int) {
  List<int> toList() => [$1, $2];
}

class _Totals {
  final pages = <Map<String, Object?>>[];
  void add(_Page p) => pages.add(p.json);

  String report(int n) {
    String pct(int a, int b) =>
        b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(1)}%';
    int err(Map<String, Object?> p, String k) => (p['errors'] as Map)[k] as int;
    bool sameStaves(Map<String, Object?> p) =>
        (p['staves'] as Map)['truth'] == (p['staves'] as Map)['scan'];

    String rates(Iterable<Map<String, Object?>> set, String label) {
      final list = set.toList();
      final tokens = list.fold(0, (a, p) => a + (p['tokens'] as int));
      int sum(String k) => list.fold(0, (a, p) => a + err(p, k));
      final better = list.where((p) => err(p, 'fixed') < err(p, 'scan'));
      final worse = list.where((p) => err(p, 'fixed') > err(p, 'scan'));
      return '$label (${list.length} pages, $tokens notes and rests):\n'
          '  error rate, pitch and length: scan ${pct(sum('scan'), tokens)}'
          ' -> after all fixes ${pct(sum('fixed'), tokens)}\n'
          '  error rate, length only:      scan '
          '${pct(sum('scanRhythm'), tokens)} -> after all fixes '
          '${pct(sum('fixedRhythm'), tokens)}\n'
          '  pages closer after fixes: ${better.length}, further: '
          '${worse.length}, same: ${list.length - better.length - worse.length}';
    }

    int full(String k, int i) => pages.fold(
      0,
      (a, p) => a + (((p['fullBars'] as Map)[k] as List)[i] as int),
    );
    final b = StringBuffer()
      ..writeln(rates(pages, 'All pages'))
      ..writeln(rates(pages.where(sameStaves), 'Pages with the same staves'))
      ..writeln(
        'Middle bars that add up: truth ${full('truth', 0)}/'
        '${full('truth', 1)}, scan ${full('scan', 0)}/${full('scan', 1)}, '
        'after fixes ${full('fixed', 0)}/${full('fixed', 1)}',
      )
      ..writeln('Checker findings (truth / scan / after fixes):');

    final issueTotals = <String, Map<String, int>>{};
    for (final p in pages) {
      final issues = p['issues'] as Map;
      for (final k in ['truth', 'scan', 'fixed']) {
        (issues[k] as Map).forEach((kind, count) {
          final t = issueTotals.putIfAbsent(kind as String, () => {});
          t[k] = (t[k] ?? 0) + (count as int);
        });
      }
    }
    issueTotals.forEach((kind, c) {
      b.writeln(
        '  ${kind.padRight(20)} ${c['truth'] ?? 0} / ${c['scan'] ?? 0} / '
        '${c['fixed'] ?? 0}',
      );
    });

    // Per kind of fix: how often, and its effect on the distance to truth.
    final kinds = <String, List<List<int>>>{};
    for (final p in pages) {
      final applied = p['applied'] as List;
      final deltas = p['deltas'] as List;
      for (var i = 0; i < applied.length; i++) {
        kinds
            .putIfAbsent(applied[i] as String, () => [])
            .add((deltas[i] as List).cast<int>());
      }
    }
    b.writeln(
      'Fixes applied (count; closer / further / no change to the truth, by '
      'pitch and length; net change in errors):',
    );
    final sorted = kinds.entries.toList()
      ..sort((x, y) => y.value.length - x.value.length);
    for (final e in sorted) {
      final d = e.value.map((v) => v[0]);
      b.writeln(
        '  ${e.value.length.toString().padLeft(4)}  ${e.key.padRight(44)} '
        '${d.where((x) => x < 0).length} / ${d.where((x) => x > 0).length} / '
        '${d.where((x) => x == 0).length}; net '
        '${d.fold(0, (a, x) => a + x)}',
      );
    }
    return b.toString();
  }
}
