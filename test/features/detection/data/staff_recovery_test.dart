import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';

// Exercise the public post-inference path without loading a native interpreter.
Float32List clefOutput(img.Image image, List<Rect> boxes) {
  const anchors = 18900;
  final raw = Float32List(28 * anchors);
  for (final (i, box) in boxes.indexed) {
    raw[i] = box.center.dx / image.width;
    raw[anchors + i] = box.center.dy / image.height;
    raw[2 * anchors + i] = box.width / image.width;
    raw[3 * anchors + i] = box.height / image.height;
    raw[5 * anchors + i] = .9; // G clef, class 1.
  }
  return raw;
}

void main() {
  test('a clef spanning two traced rows does not add a staff between them', () {
    final image = img.Image(width: 600, height: 400)
      ..clear(img.ColorRgb8(255, 255, 255));
    for (final top in [100, 250]) {
      for (var line = 0; line < 5; line++) {
        img.drawLine(
          image,
          x1: 20,
          y1: top + 12 * line,
          x2: 580,
          y2: top + 12 * line,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
    final result = TfliteSymbolDetector().detectFromOutput(
      image,
      [],
      clefOutput(image, const [
        Rect.fromLTWH(25, 88, 25, 72),
        Rect.fromLTWH(25, 238, 25, 72),
        Rect.fromLTWH(20, 88, 35, 222),
      ]),
    );
    expect(result.staffs, hasLength(2));
    expect(result.staffs.every((s) => s.id.startsWith('traced-')), isTrue);
  });

  test(
    'untraced clefs still recover distinct rows without duplicating one',
    () {
      final image = img.Image(width: 600, height: 400)
        ..clear(img.ColorRgb8(255, 255, 255));
      final result = TfliteSymbolDetector().detectFromOutput(
        image,
        [],
        clefOutput(image, const [
          Rect.fromLTWH(25, 88, 25, 72),
          Rect.fromLTWH(250, 90, 25, 72),
          Rect.fromLTWH(25, 238, 25, 72),
        ]),
      );
      expect(result.staffs, hasLength(2));
      expect(result.staffs.every((s) => s.id.startsWith('clef-')), isTrue);
    },
  );

  test('sparse photo merged clef retains exactly its eight sloped rows', () {
    const root = 'test/fixtures/barlines/sparse';
    final frozen = DetectionResult.fromJson(
      jsonDecode(File('$root.detection.json').readAsStringSync()),
    );
    final image = img.grayscale(
      img.decodeJpg(File('$root.jpg').readAsBytesSync())!,
    );
    final boxes = frozen.symbols
        .where((s) => s.musicSymbol == MusicSymbol.clefG)
        .map((s) => s.boundingBox!)
        .toList();
    final result = TfliteSymbolDetector().detectFromOutput(
      image,
      [],
      clefOutput(image, boxes),
    );
    expect(result.staffs, hasLength(8));
    expect(result.staffs.every((s) => s.id.startsWith('traced-')), isTrue);
    // Re-tracing must preserve the actual lines, including the last row that
    // used to lose its notes to the giant synthesized staff above it.
    expect(
      result.staffs.map((s) => s.lineYs),
      frozen.staffs
          .where((s) => s.id.startsWith('traced-'))
          .map((s) => s.lineYs),
    );
  });
}
