import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:note_vision/core/models/score.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/staff_line_tracer.dart';

void main() {
  const tracer = StaffLineTracer();
  for (final missing in [0, 4]) {
    test('a ledger run cannot replace staff line $missing', () {
      final image = img.Image(width: 900, height: 400)
        ..clear(img.ColorRgb8(200, 200, 200));
      for (var line = 0; line < 5; line++) {
        for (var x = 20; x < 880; x++) {
          if (line == missing && x >= 200 && x < 550) continue;
          image.setPixelRgb(x, 100 + line * 12, 25, 25, 25);
          image.setPixelRgb(x, 101 + line * 12, 25, 25, 25);
        }
      }
      final ledger = missing == 0 ? 160 : 88;
      for (var x = 200; x < 550; x++) {
        image.setPixelRgb(x, ledger, 25, 25, 25);
        image.setPixelRgb(x, ledger + 1, 25, 25, 25);
      }
      final candidates = tracer.candidates(image);
      final staff = tracer.staffAtClef(
        candidates,
        isGClef: true,
        // The displaced clef box fits the false run better geometrically.
        clef: Rect.fromLTWH(250, missing == 0 ? 100 : 76, 30, 72),
        id: 's',
      )!;
      expect(staff.lineYs.first, closeTo(100.5, 1));
      expect(staff.lineYs.last, closeTo(148.5, 1));
    });
  }

  test('a genuinely shorter staff keeps its independent five tracks', () {
    final image = img.Image(width: 900, height: 400)
      ..clear(img.ColorRgb8(200, 200, 200));
    for (final (top, from, to) in [(100, 20, 880), (250, 180, 480)]) {
      for (var line = 0; line < 5; line++) {
        for (var x = from; x < to; x++) {
          image.setPixelRgb(x, top + line * 12, 25, 25, 25);
          image.setPixelRgb(x, top + line * 12 + 1, 25, 25, 25);
        }
      }
    }
    final staff = tracer.staffAtClef(
      tracer.candidates(image),
      isGClef: true,
      clef: const Rect.fromLTWH(180, 238, 30, 72),
      id: 'short',
    )!;
    expect(staff.lineYs.first, closeTo(250.5, 1));
    expect(staff.lineYs.last, closeTo(298.5, 1));
  });

  test('song retains its real second staff and both written boundaries', () {
    const root = 'test/fixtures/barlines/song';
    final frozen = DetectionResult.fromJson(
      jsonDecode(File('$root.detection.json').readAsStringSync()),
    );
    final photo = img.grayscale(
      img.decodeJpg(File('$root.jpg').readAsBytesSync())!,
    );
    final staves = tracer.stavesAtClefs(tracer.candidates(photo), [
      for (final symbol in frozen.symbols)
        if (symbol.type == 'clefG' || symbol.type == 'clefF')
          (isGClef: symbol.type == 'clefG', box: symbol.boundingBox!),
    ]);
    expect(staves, hasLength(5));
    expect(staves[1].offsetXs.last, greaterThan(600));
    final lines = const BarlineFinder().find(photo, staves, frozen.symbols);
    final second = lines.where((b) => b.staffId == staves[1].id).toList();
    expect(second, hasLength(2));
    expect(second[0].x, closeTo(343, 3));
    expect(second[1].x, closeTo(612, 3));
    // The note stem at x241 must remain a stem, beyond the staff's top.
    expect(second.any((b) => (b.x - 241).abs() < 4), isFalse);
    const mapper = DetectionToScoreMapperService();
    final score = mapper
        .map(
          DetectionResult(
            staffs: staves,
            symbols: frozen.symbols,
            barlines: lines,
          ),
        )
        .score;
    expect(score.parts.map((p) => p.measures.length), List.filled(5, 3));
    expect(score.parts[1].measures.any((m) => m.unresolvedBarlines), isFalse);
    // The first written note is middle C on a ledger line, below the staff.
    expect(score.parts[1].measures.first.notes.first.pitch, 'C4');
    final before = mapper.map(frozen).score;
    expect(before.parts[1].measures.first.notes.first.pitch, 'E4');
    List<Map<String, dynamic>> values(Score score) => [
      for (final p in score.parts)
        for (final m in p.measures)
          for (final s in m.symbols)
            s.toJson()
              ..remove('step')
              ..remove('octave'),
    ];
    expect(values(score), values(before));
    final withoutHead = frozen.symbols
        .where(
          (s) =>
              !(s.musicSymbol?.isNote == true &&
                  s.x < 260 &&
                  s.x + (s.width ?? 0) > 220 &&
                  s.y > 330 &&
                  s.y < 450),
        )
        .toList();
    expect(withoutHead.length, lessThan(frozen.symbols.length));
    final missed = const BarlineFinder()
        .find(photo, staves, withoutHead)
        .where((b) => b.staffId == staves[1].id)
        .toList();
    expect(missed, hasLength(2));
    expect(missed.any((b) => (b.x - 241).abs() < 4), isFalse);
  });
}
