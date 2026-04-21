import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/preprocessing/data/horizontal_projection_staff_detector.dart';

/// Builds a white RGB PNG of [width]×[height] with fully black rows at each Y
/// in [lineRows]. Used to create synthetic score images with known line positions.
Uint8List _makeTestPng({
  required int width,
  required int height,
  required List<int> lineRows,
}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (final y in lineRows) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  const detector = HorizontalProjectionStaffDetector();

  group('HorizontalProjectionStaffDetector', () {
    test('detects a single stave of 5 evenly spaced lines', () {
      // Lines at rows 20, 30, 40, 50, 60 — spacing = 10px
      final png = _makeTestPng(
        width: 200,
        height: 200,
        lineRows: [20, 30, 40, 50, 60],
      );

      final staves = detector.detect(png);

      expect(staves, hasLength(1));
      final staff = staves.first;
      expect(staff.lineYs, hasLength(5));

      // Each line centre should be within 1px of the target row
      final expected = [20.0, 30.0, 40.0, 50.0, 60.0];
      for (int i = 0; i < 5; i++) {
        expect(staff.lineYs[i], closeTo(expected[i], 1.0));
      }
    });

    test('topY is above first line and bottomY is below last line', () {
      final png = _makeTestPng(
        width: 200,
        height: 200,
        lineRows: [20, 30, 40, 50, 60],
      );

      final staves = detector.detect(png);
      final staff = staves.first;

      // topY should be extended above line 1 by ~half spacing (5px)
      expect(staff.topY, lessThan(20.0));
      // bottomY should be extended below line 5 by ~half spacing (5px)
      expect(staff.bottomY, greaterThan(60.0));
    });

    test('detects two staves when 10 lines are present', () {
      // Stave 1: rows 20, 30, 40, 50, 60
      // Stave 2: rows 120, 130, 140, 150, 160
      // Gap between staves (~60px) >> median spacing (10px) → two staves
      final png = _makeTestPng(
        width: 200,
        height: 300,
        lineRows: [20, 30, 40, 50, 60, 120, 130, 140, 150, 160],
      );

      final staves = detector.detect(png);

      expect(staves, hasLength(2));
      expect(staves[0].lineYs, hasLength(5));
      expect(staves[1].lineYs, hasLength(5));

      // First stave lines cluster around 20–60, second around 120–160
      expect(staves[0].lineYs.first, closeTo(20.0, 1.0));
      expect(staves[1].lineYs.first, closeTo(120.0, 1.0));
    });

    test('stave ids are sequential', () {
      final png = _makeTestPng(
        width: 200,
        height: 300,
        lineRows: [20, 30, 40, 50, 60, 120, 130, 140, 150, 160],
      );

      final staves = detector.detect(png);

      expect(staves[0].id, 'staff-0');
      expect(staves[1].id, 'staff-1');
    });

    test('returns empty list when image has no dark rows', () {
      // Fully white image — no candidate rows at all
      final png = _makeTestPng(width: 200, height: 200, lineRows: []);

      final staves = detector.detect(png);

      expect(staves, isEmpty);
    });

    test('returns empty list when fewer than 5 lines are present', () {
      // Only 4 lines — cannot form a complete stave
      final png = _makeTestPng(
        width: 200,
        height: 200,
        lineRows: [20, 30, 40, 50],
      );

      final staves = detector.detect(png);

      expect(staves, isEmpty);
    });

    test('topY and bottomY are clamped to image bounds', () {
      // Lines very near the top — topY should not go negative
      final png = _makeTestPng(
        width: 200,
        height: 200,
        lineRows: [2, 6, 10, 14, 18],
      );

      final staves = detector.detect(png);

      expect(staves, hasLength(1));
      expect(staves.first.topY, greaterThanOrEqualTo(0.0));
      expect(staves.first.bottomY, lessThanOrEqualTo(200.0));
    });
  });
}
