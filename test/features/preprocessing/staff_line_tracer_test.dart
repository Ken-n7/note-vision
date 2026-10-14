import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/preprocessing/data/staff_line_tracer.dart';

/// A grey page with one hand-ruled staff: unevenly spaced lines that climb
/// [slope] pixels per pixel from [x0] to [x1].
img.Image _slopedStaff({
  required List<double> lineYsAtX0,
  required double slope,
  int width = 900,
  int height = 400,
  int x0 = 40,
  int x1 = 860,
}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(190, 190, 190));
  for (final lineY in lineYsAtX0) {
    for (var x = x0; x < x1; x++) {
      final y = (lineY - slope * (x - x0)).round();
      image.setPixelRgb(x, y, 30, 30, 30);
      image.setPixelRgb(x, y + 1, 30, 30, 30);
    }
  }
  return image;
}

void main() {
  const tracer = StaffLineTracer();

  group('DetectedStaff.offsetAt', () {
    const staff = DetectedStaff(
      id: 's',
      topY: 90,
      bottomY: 150,
      lineYs: [100, 110, 120, 130, 140],
      offsetXs: [100, 200, 300],
      offsetYs: [0, -10, -30],
    );

    test('interpolates between samples and keeps its slope past the ends', () {
      expect(staff.offsetAt(150), -5);
      expect(staff.offsetAt(250), -20);
      expect(staff.offsetAt(50), 7.5); // overall slope of -0.15 carried left
      expect(staff.offsetAt(400), -45);
    });

    test('a level staff has no offset and survives a JSON round trip', () {
      const level = DetectedStaff(
        id: 'l',
        topY: 0,
        bottomY: 10,
        lineYs: [1, 2, 3, 4, 5],
      );
      expect(level.offsetAt(123), 0);
      expect(DetectedStaff.fromJson(level.toJson()), level);
      expect(DetectedStaff.fromJson(staff.toJson()), staff);
    });

    test('containsY follows the staff where it runs', () {
      expect(staff.containsY(140, x: 100), isTrue);
      expect(staff.containsY(140, x: 300), isFalse); // staff is 30 px higher there
      expect(staff.containsY(70, x: 300), isTrue);
      expect(staff.containsY(70, x: 100), isFalse);
    });
  });

  group('StaffLineTracer', () {
    test('follows a sloped, unevenly ruled staff', () {
      // Gaps of 14, 20, 16 and 22 px; the lines climb 6 px per 100 px.
      final image = _slopedStaff(
        lineYsAtX0: [200, 214, 234, 250, 272],
        slope: 0.06,
      );

      final candidates = tracer.candidates(image);
      expect(candidates, hasLength(1));

      final staff = tracer.staffAtClef(
        candidates,
        isGClef: true,
        clef: Rect.fromCenter(
          center: const Offset(70, 234),
          width: 40,
          height: 72 * StaffLineTracer.gClefHeightInStaves,
        ),
        id: 'traced',
      )!;

      // Each line is where it was drawn, at both ends of the page.
      for (final x in [100.0, 450.0, 800.0]) {
        final drawn = [200, 214, 234, 250, 272]
            .map((y) => y + 0.5 - 0.06 * (x - 40))
            .toList();
        for (var i = 0; i < 5; i++) {
          expect(
            staff.lineYs[i] + staff.offsetAt(x),
            closeTo(drawn[i], 2.0),
            reason: 'line $i at x=$x',
          );
        }
      }
    });

    test('a clef nowhere near the lines gets no staff', () {
      final image = _slopedStaff(
        lineYsAtX0: [200, 214, 234, 250, 272],
        slope: 0,
      );
      final staff = tracer.staffAtClef(
        tracer.candidates(image),
        isGClef: true,
        clef: Rect.fromCenter(
          center: const Offset(70, 60),
          width: 40,
          height: 100,
        ),
        id: 'traced',
      );
      expect(staff, isNull);
    });

    test('finds all nine bent staves on a real handwritten page', () {
      // A phone photo of a hand-ruled page, 904x1200 as the picker delivers
      // it. The clef boxes are the model's own detections on this photo.
      final image = img.decodeImage(
        File('test/fixtures/handwritten_treble_page.jpg').readAsBytesSync(),
      )!;
      const clefs = [
        [51.5, 115.6, 41.3, 112.7],
        [51.4, 248.1, 48.6, 122.2],
        [49.4, 378.4, 51.8, 142.2],
        [46.4, 508.2, 46.4, 123.2],
        [48.4, 660.4, 43.2, 164.1],
        [40.6, 758.2, 52.4, 133.8],
        [42.8, 892.4, 55.5, 145.2],
        [42.8, 1025.4, 55.3, 123.6],
        [51.7, 1111.8, 68.6, 171.9],
      ];

      final staves = tracer.stavesAtClefs(tracer.candidates(image), [
        for (final c in clefs)
          (
            isGClef: true,
            box: Rect.fromCenter(
              center: Offset(c[0], c[1]),
              width: c[2],
              height: c[3],
            ),
          ),
      ]);

      // One staff under each clef, top to bottom, none of them a mix of two
      // neighbouring staves (those come out 100 px tall or more).
      expect(staves, hasLength(9));
      for (var i = 0; i < 9; i++) {
        expect(
          staves[i].containsY(clefs[i][1], x: clefs[i][0]),
          isTrue,
          reason: 'clef $i sits on staff $i',
        );
        expect(staves[i].lineYs.last - staves[i].lineYs.first, lessThan(100));
      }
      // The paper bends: several staves end well above or below where they start.
      final rises = [
        for (final s in staves) (s.offsetAt(860) - s.offsetAt(60)).abs(),
      ];
      expect(rises.where((r) => r > 15), isNotEmpty);
    });
  });
}
