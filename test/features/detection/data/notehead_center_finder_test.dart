import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/mapping/domain/internal/pitch_calculator.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/notehead_center_finder.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';

img.Image paper([int width = 300, int height = 300]) =>
    img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(200, 200, 200));

void ellipse(
  img.Image image,
  double x,
  double y,
  double rx,
  double ry, {
  int value = 25,
}) {
  for (var yy = 0; yy < image.height; yy++) {
    for (var xx = 0; xx < image.width; xx++) {
      final dx = (xx + .5 - x) / rx, dy = (yy + .5 - y) / ry;
      if (dx * dx + dy * dy <= 1) {
        image.setPixelRgb(xx, yy, value, value, value);
      }
    }
  }
}

void main() {
  const finder = NoteheadCenterFinder();
  for (final scale in [1, 2]) {
    for (final top in [false, true]) {
      test('solid ${top ? 'upper' : 'lower'} head at scale $scale', () {
        final image = paper(300 * scale, 300 * scale);
        final band = Rect.fromLTWH(
          100.0 * scale,
          (top ? 100.0 : 170.0) * scale,
          30.0 * scale,
          30.0 * scale,
        );
        final estimate = Rect.fromCenter(
          center: band.center,
          width: 30.0 * scale,
          height: 16.0 * scale,
        );
        final y = (top ? 109.5 : 190.5) * scale;
        ellipse(image, 115.0 * scale, y, 10.0 * scale, 6.0 * scale);
        final ink = img.ColorRgb8(25, 25, 25);
        img.fillRect(
          image,
          x1: 122 * scale,
          y1: top ? 110 * scale : 100 * scale,
          x2: 123 * scale,
          y2: top ? 199 * scale : 190 * scale,
          color: ink,
        );
        img.fillRect(
          image,
          x1: 80 * scale,
          y1: (top ? 110 : 190) * scale,
          x2: 150 * scale,
          y2: (top ? 110 : 190) * scale + scale - 1,
          color: ink,
        );
        final before = image.getBytes().toList();
        final head = finder.refine(image, band: band, estimate: estimate);
        expect(head.center.dy, closeTo(y, .6 * scale));
        expect(head.center.dx, estimate.center.dx);
        expect(head.size, estimate.size);
        expect(image.getBytes(), before);
      });
    }
  }

  const band = Rect.fromLTWH(100, 170, 30, 30);
  final estimate = Rect.fromCenter(center: band.center, width: 30, height: 16);
  for (final shape in [
    'blank',
    'staff and stem',
    'thick staff',
    'hollow',
    'clipped head',
    'low contrast',
  ]) {
    test('$shape keeps the original estimate', () {
      final image = paper();
      final ink = img.ColorRgb8(25, 25, 25);
      switch (shape) {
        case 'staff and stem':
          img.fillRect(image, x1: 80, y1: 180, x2: 160, y2: 181, color: ink);
          img.fillRect(image, x1: 122, y1: 150, x2: 123, y2: 220, color: ink);
        case 'thick staff':
          img.fillRect(image, x1: 80, y1: 180, x2: 160, y2: 191, color: ink);
        case 'hollow':
          ellipse(image, 115, 190.5, 10, 6);
          ellipse(image, 115, 190.5, 6, 3, value: 200);
        case 'clipped head':
          ellipse(image, 102, 190.5, 10, 6);
        case 'low contrast':
          ellipse(image, 115, 190.5, 10, 6, value: 190);
      }
      expect(
        finder.refine(image, band: band, estimate: estimate),
        same(estimate),
      );
    });
  }

  test('binary and 8-bit images use the same contrast scale', () {
    final image = img.Image(width: 300, height: 300)
      ..clear(img.ColorRgb8(255, 255, 255));
    ellipse(image, 115, 190.5, 10, 6, value: 0);
    final binary = image.convert(format: img.Format.uint1, numChannels: 1);
    final eight = finder.refine(image, band: band, estimate: estimate);
    final one = finder.refine(binary, band: band, estimate: estimate);
    expect(eight.center.dy, closeTo(190.5, .6));
    expect(one, eight);
  });

  test('competing solid blobs keep the estimate', () {
    const band = Rect.fromLTWH(0, 0, 100, 40);
    const estimate = Rect.fromLTWH(0, 4, 100, 12);
    final one = paper(120, 60);
    ellipse(one, 25, 20, 22, 8);
    expect(
      finder.refine(one, band: band, estimate: estimate).center.dy,
      closeTo(20, .6),
    );
    ellipse(one, 75, 20, 22, 8);
    expect(finder.refine(one, band: band, estimate: estimate), same(estimate));
  });

  test('outside, tiny and non-finite bands fall back safely', () {
    for (final b in [
      const Rect.fromLTWH(-1, 0, 20, 20),
      const Rect.fromLTWH(299, 200, 20, 20),
      const Rect.fromLTWH(0, 0, 2, 2),
      Rect.fromLTWH(double.nan, 0, 30, 30),
    ]) {
      expect(
        finder.refine(paper(), band: b, estimate: estimate),
        same(estimate),
      );
    }
  });

  test('centering needs one-ended beam evidence', () {
    final image = paper();
    ellipse(image, 115, 190.5, 10, 6);
    const box = Rect.fromLTWH(100, 100, 30, 100);
    for (final beams in <List<Rect>>[
      [],
      [
        const Rect.fromLTWH(100, 100, 80, 10),
        const Rect.fromLTWH(100, 190, 80, 10),
      ],
    ]) {
      expect(
        TfliteSymbolDetector.noteheadRect(
          image,
          box,
          beams: beams,
          refineCenter: true,
        ),
        TfliteSymbolDetector.noteheadRect(image, box, beams: beams),
      );
    }
  });

  test('decoder changes only the pitch estimate and fixes F4 to E4', () {
    final image = paper();
    ellipse(image, 115, 190.5, 10, 6);
    img.fillRect(
      image,
      x1: 122,
      y1: 100,
      x2: 123,
      y2: 190,
      color: img.ColorRgb8(25, 25, 25),
    );
    const box = Rect.fromLTWH(100, 100, 30, 100);
    const staff = DetectedStaff(
      id: 's',
      topY: 140,
      bottomY: 200,
      lineYs: [150, 160, 170, 180, 190],
    );
    const anchors = 18900;
    final raw = Float32List(28 * anchors);
    for (final (i, cls, r) in [
      (0, 5, box),
      (1, 9, const Rect.fromLTWH(110, 95, 90, 10)),
    ]) {
      raw[i] = r.center.dx / image.width;
      raw[anchors + i] = r.center.dy / image.height;
      raw[2 * anchors + i] = r.width / image.width;
      raw[3 * anchors + i] = r.height / image.height;
      raw[(4 + cls) * anchors + i] = .9;
    }
    final detection = TfliteSymbolDetector().detectFromOutput(image, [
      staff,
    ], raw);
    final note = detection.symbols.single;
    expect(note.boundingBox!.center.dy, closeTo(185, .001));
    expect(note.pitchBoundingBox!.center.dy, closeTo(190.5, .6));
    expect(note.metadata?['noteType'], 'eighth');
    final legacyMetadata = {...note.metadata!}..remove('pitchBox');
    const calc = PitchCalculator();
    const clef = Clef(sign: 'G', line: 2);
    final before = calc.calculate(
      symbol: note.copyWith(metadata: legacyMetadata),
      staff: staff,
      clef: clef,
    )!;
    final after = calc.calculate(symbol: note, staff: staff, clef: clef)!;
    expect('${before.step}${before.octave}', 'F4');
    expect('${after.step}${after.octave}', 'E4');
    expect(
      DetectionResult.fromJson(
        jsonDecode(jsonEncode(detection.toJson())),
      ).symbols.single,
      note,
    );
  });

  final cases =
      jsonDecode(
            File('test/fixtures/barlines/head_centers.json').readAsStringSync(),
          )
          as List;
  for (final sample in cases) {
    test(
      '${sample['photo']} ${sample['id']}: ${sample['fit'] == true ? 'fit' : 'keep uncertain estimate'}',
      () {
        final photo = sample['photo'] as String;
        final frozen = DetectionResult.fromJson(
          jsonDecode(
            File(
              'test/fixtures/barlines/$photo.detection.json',
            ).readAsStringSync(),
          ),
        );
        final symbol = frozen.symbols.singleWhere((s) => s.id == sample['id']);
        final image = img.grayscale(
          img.decodeJpg(
            File('test/fixtures/barlines/$photo.jpg').readAsBytesSync(),
          )!,
        );
        final beams = [
          for (final b in sample['beams'])
            Rect.fromLTRB(
              (b[0] as num).toDouble(),
              (b[1] as num).toDouble(),
              (b[2] as num).toDouble(),
              (b[3] as num).toDouble(),
            ),
        ];
        final before = TfliteSymbolDetector.noteheadRect(
          image,
          symbol.fullBoundingBox!,
          beams: beams,
        );
        final after = TfliteSymbolDetector.noteheadRect(
          image,
          symbol.fullBoundingBox!,
          beams: beams,
          refineCenter: true,
        );
        final low = (sample['centerMin'] as num).toDouble();
        final high = (sample['centerMax'] as num).toDouble();
        if (sample['fit'] == true) {
          expect(after.center.dy, inInclusiveRange(low, high));
        } else {
          // The head remains visibly offset, but its clipped/weak support
          // does not justify overriding the established estimate.
          expect(after, before);
        }
        expect(before.center.dy < low || before.center.dy > high, isTrue);
        expect(after.center.dx, before.center.dx);
        expect(after.size, before.size);
      },
    );
  }
}
