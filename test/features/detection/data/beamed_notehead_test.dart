import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/internal/pitch_calculator.dart';

const box = Rect.fromLTWH(100, 100, 20, 80);
const upperBeam = Rect.fromLTWH(90, 95, 110, 20);
const lowerBeam = Rect.fromLTWH(90, 165, 110, 20);

img.Image noteImage({required bool headAtTop}) {
  final image = img.Image(width: 400, height: 300)
    ..clear(img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  img.fillRect(image, x1: 118, y1: 100, x2: 119, y2: 179, color: black);
  final y = headAtTop ? 101 : 164;
  img.fillRect(image, x1: 100, y1: y, x2: 119, y2: y + 13, color: black);
  final beam = headAtTop ? lowerBeam : upperBeam;
  img.fillRect(
    image,
    x1: beam.left.toInt(),
    y1: beam.top.toInt(),
    x2: beam.right.toInt(),
    y2: beam.bottom.toInt(),
    color: black,
  );
  return image;
}

Rect rect(List<dynamic> values) => Rect.fromLTRB(
  (values[0] as num).toDouble(),
  (values[1] as num).toDouble(),
  (values[2] as num).toDouble(),
  (values[3] as num).toDouble(),
);

void main() {
  for (final headAtTop in [false, true]) {
    test(
      'a dark beam does not become the ${headAtTop ? 'upper' : 'lower'} head',
      () {
        final image = noteImage(headAtTop: headAtTop);
        final fallback = TfliteSymbolDetector.noteheadRect(image, box);
        final head = TfliteSymbolDetector.noteheadRect(
          image,
          box,
          beams: [headAtTop ? lowerBeam : upperBeam],
        );
        expect(fallback.center.dy, headAtTop ? 168 : 112);
        expect(head.center.dy, headAtTop ? 112 : 168);
        expect(head.size, fallback.size);
      },
    );
  }

  for (final beams in <List<Rect>>[
    [],
    [upperBeam, lowerBeam],
    [const Rect.fromLTWH(100, 95, 20, 90)],
    [const Rect.fromLTWH(121, 95, 110, 20)],
    [const Rect.fromLTWH(100, 130, 20, 10)],
  ]) {
    test(
      'absent, ambiguous or unrelated beam keeps the ink fallback: $beams',
      () {
        final image = noteImage(headAtTop: false);
        expect(
          TfliteSymbolDetector.noteheadRect(image, box, beams: beams),
          TfliteSymbolDetector.noteheadRect(image, box),
        );
      },
    );
  }

  test('a beam just beyond a short stem still selects the opposite head', () {
    expect(
      TfliteSymbolDetector.noteheadRect(
        noteImage(headAtTop: false),
        box,
        beams: [const Rect.fromLTWH(110, 92, 80, 7)],
      ).center.dy,
      168,
    );
  });

  test(
    'public decoder refines pitch without changing association geometry',
    () {
      final image = noteImage(headAtTop: false);
      const staff = DetectedStaff(
        id: 's',
        topY: 120,
        bottomY: 180,
        lineYs: [130, 140, 150, 160, 170],
      );
      const anchors = 18900;
      final raw = Float32List(28 * anchors);
      void add(int i, int cls, Rect r) {
        raw[i] = r.center.dx / image.width;
        raw[anchors + i] = r.center.dy / image.height;
        raw[2 * anchors + i] = r.width / image.width;
        raw[3 * anchors + i] = r.height / image.height;
        raw[(4 + cls) * anchors + i] = .9;
      }

      add(0, 5, box); // Quarter box plus a detected beam.
      add(1, 9, upperBeam);
      final result = TfliteSymbolDetector().detectFromOutput(image, [
        staff,
      ], raw);
      final note = result.symbols.single;
      expect(note.metadata?['beamed'], true);
      expect(note.metadata?['noteType'], 'eighth');
      expect(note.confidence, closeTo(.9, 1e-6));
      expect(note.boundingBox!.center.dy, closeTo(112, 1e-4));
      expect(note.pitchBoundingBox!.center.dy, closeTo(168, 1e-4));
      expect(note.fullBoundingBox!.center.dy, closeTo(140, 1e-4));
      final pitch = const PitchCalculator().calculate(
        symbol: note,
        staff: staff,
        clef: const Clef(sign: 'G', line: 2),
      );
      expect('${pitch!.step}${pitch.octave}', 'E4');
      final roundTrip = DetectionResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())),
      );
      expect(roundTrip.symbols.single, note);
    },
  );

  for (final cls in [2, 3, 6, 7]) {
    test('explicit note class $cls retains its existing head estimate', () {
      final image = noteImage(headAtTop: false);
      const anchors = 18900;
      final raw = Float32List(28 * anchors);
      for (final (i, type, r) in [(0, cls, box), (1, 9, upperBeam)]) {
        raw[i] = r.center.dx / image.width;
        raw[anchors + i] = r.center.dy / image.height;
        raw[2 * anchors + i] = r.width / image.width;
        raw[3 * anchors + i] = r.height / image.height;
        raw[(4 + type) * anchors + i] = .9;
      }
      final result = TfliteSymbolDetector().detectFromOutput(image, const [
        DetectedStaff(
          id: 's',
          topY: 90,
          bottomY: 190,
          lineYs: [100, 120, 140, 160, 180],
        ),
      ], raw);
      final note = result.symbols.single;
      expect(note.metadata?.containsKey('pitchBox'), isFalse);
      expect(note.pitchBoundingBox, note.boundingBox);
    });
  }

  final cases =
      jsonDecode(
            File('test/fixtures/barlines/beamed_heads.json').readAsStringSync(),
          )
          as List;
  for (final sample in cases) {
    final photo = sample['photo'] as String;
    test('$photo: written head ends stay opposite their beams', () {
      final image = img.grayscale(
        img.decodeJpg(
          File('test/fixtures/barlines/$photo.jpg').readAsBytesSync(),
        )!,
      );
      final frozen = DetectionResult.fromJson(
        jsonDecode(
          File(
            'test/fixtures/barlines/$photo.detection.json',
          ).readAsStringSync(),
        ),
      );
      final beams = [for (final b in sample['beams']) rect(b)];
      for (final expected in sample['notes']) {
        final symbol = frozen.symbols.singleWhere(
          (s) => s.id == expected['id'],
        );
        final full = symbol.fullBoundingBox!;
        final head = TfliteSymbolDetector.noteheadRect(
          image,
          full,
          beams: beams,
        );
        final y = expected['headAtTop'] == true
            ? full.top + full.height * .15
            : full.bottom - full.height * .15;
        expect(head.center.dy, closeTo(y, 1e-6), reason: '$photo ${symbol.id}');
        expect(
          (head.center.dy - symbol.boundingBox!.center.dy).abs(),
          greaterThan(full.height * .5),
        );
      }
    });
  }
}
