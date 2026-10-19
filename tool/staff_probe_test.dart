// Dev tool, not part of the test suite: runs staff finding over a folder of
// photos and writes what it found, so results can be checked against real
// pages.
//
//   NV_PROBE_DIR=/path/to/jpgs NV_PROBE_TAG=new flutter test tool/staff_probe_test.dart
//
// Reads <dir>/meta.json: {photo name: {clefs: [[cx, cy, w, h, class], ...]}}
// with boxes as fractions of the image and class 1 = G clef, 0 = F clef.
// Writes <dir>/staves_<tag>.json: {photo name: [staff json, ...]}.
// NV_PROBE_TAG=old runs the straight-row projection instead of the tracer.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';
import 'package:note_vision/features/preprocessing/data/staff_line_tracer.dart';

void main() {
  test('staff probe', () {
    final dir = Platform.environment['NV_PROBE_DIR'];
    if (dir == null) return;
    final tag = Platform.environment['NV_PROBE_TAG'] ?? 'new';
    final meta = jsonDecode(File('$dir/meta.json').readAsStringSync())
        as Map<String, dynamic>;
    const tracer = StaffLineTracer();
    final out = <String, Object>{};
    final watch = Stopwatch();
    for (final name in meta.keys.toList()..sort()) {
      // Same input the app hands the detector: a grayscale image.
      final gray = img.grayscale(
        img.decodeImage(File('$dir/$name.jpg').readAsBytesSync())!,
      );
      if (tag == 'old') {
        out[name] = const HorizontalProjectionStaffDetector()
            .detect(img.encodePng(gray))
            .map((s) => s.toJson())
            .toList();
        continue;
      }
      watch.start();
      final candidates = tracer.candidates(gray);
      watch.stop();
      final clefs = (meta[name]['clefs'] as List<dynamic>?) ?? const [];
      final staves = tracer.stavesAtClefs(candidates, [
        for (final c in clefs.cast<List<dynamic>>())
          (
            isGClef: c[4] == 1,
            box: Rect.fromCenter(
              center: Offset(
                (c[0] as num) * gray.width.toDouble(),
                (c[1] as num) * gray.height.toDouble(),
              ),
              width: (c[2] as num) * gray.width.toDouble(),
              height: (c[3] as num) * gray.height.toDouble(),
            ),
          ),
      ]).map((s) => s.toJson()).toList();
      // Model classes in dataset order -> what the app turns them into.
      const classes = <(MusicSymbol, String?)>[
        (MusicSymbol.clefF, null), (MusicSymbol.clefG, null),
        (MusicSymbol.noteheadBlackInSpace, 'eighth'),
        (MusicSymbol.noteheadHalfInSpace, 'half'), (MusicSymbol.restHalf, null),
        (MusicSymbol.noteheadBlackInSpace, 'quarter'),
        (MusicSymbol.noteheadBlackInSpace, 'sixteenth'),
        (MusicSymbol.noteheadWholeInSpace, 'whole'), (MusicSymbol.restWhole, null),
        (MusicSymbol.beam, null), (MusicSymbol.accidentalSharp, null),
        (MusicSymbol.accidentalFlat, null), (MusicSymbol.accidentalNatural, null),
        (MusicSymbol.restQuarter, null), (MusicSymbol.rest8th, null),
        (MusicSymbol.rest16th, null),
      ];
      final symbols = [
        for (final c in ((meta[name]['boxes'] as List<dynamic>?) ?? const [])
            .cast<List<dynamic>>())
          if ((c[4] as num).toInt() < classes.length)
            DetectedSymbol.fromMusicSymbol(
              id: 'p',
              symbol: classes[(c[4] as num).toInt()].$1,
              boundingBox: Rect.fromCenter(
                center: Offset((c[0] as num) * gray.width.toDouble(),
                    (c[1] as num) * gray.height.toDouble()),
                width: (c[2] as num) * gray.width.toDouble(),
                height: (c[3] as num) * gray.height.toDouble(),
              ),
              metadata: classes[(c[4] as num).toInt()].$2 == null
                  ? null
                  : {'noteType': classes[(c[4] as num).toInt()].$2},
            ),
      ];
      final barlines = const BarlineFinder().find(gray, [
        for (final s in staves) DetectedStaff.fromJson(s.cast<String, dynamic>()),
      ], symbols);
      for (final s in staves) {
        s['barlines'] = [
          for (final b in barlines)
            if (b.staffId == s['id']) b.x,
        ];
      }
      out[name] = staves;
    }
    // ignore: avoid_print
    print('tracing took ${watch.elapsedMilliseconds ~/ meta.length} ms per photo (debug build)');
    File('$dir/staves_$tag.json').writeAsStringSync(jsonEncode(out));
  }, timeout: Timeout.none);
}
