import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';

void main() {
  group('TfliteSymbolDetector confidence thresholds', () {
    test('rests use the lower per-class threshold', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(MusicSymbol.restHalf),
        0.30,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(MusicSymbol.restWhole),
        0.30,
      );
    });

    test('falls back to the default threshold for other classes', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.noteheadBlackInSpace,
        ),
        0.40,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(MusicSymbol.clefG),
        0.40,
      );
    });

    test('falls back to the default threshold for unknown class names', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdForName('madeUpSymbol'),
        0.40,
      );
    });
  });

  group('TfliteSymbolDetector.beamedNoteType', () {
    // Stem-up note: head at the bottom, stem tip at y=100.
    const note = Rect.fromLTRB(100, 100, 120, 180);
    const beam = Rect.fromLTRB(110, 95, 200, 105);
    const secondBeam = Rect.fromLTRB(110, 108, 200, 118);

    test('no beam on the note keeps it a quarter', () {
      expect(TfliteSymbolDetector.beamedNoteType(note, const []), 'quarter');
      // A beam over a neighbouring group does not count.
      expect(
        TfliteSymbolDetector.beamedNoteType(
          note,
          const [Rect.fromLTRB(140, 95, 220, 105)],
        ),
        'quarter',
      );
    });

    test('one beam makes an eighth, two a sixteenth', () {
      expect(TfliteSymbolDetector.beamedNoteType(note, const [beam]), 'eighth');
      expect(
        TfliteSymbolDetector.beamedNoteType(note, const [beam, secondBeam]),
        'sixteenth',
      );
    });

    test('a beam just past a short stem still counts', () {
      expect(
        TfliteSymbolDetector.beamedNoteType(
          note,
          const [Rect.fromLTRB(110, 86, 200, 95)],
        ),
        'eighth',
      );
    });
  });

  group('TfliteSymbolDetector.noteheadRect', () {
    // A 20×80 white note box with a dark 20×20 blob at one end and a thin
    // 2px stem running the full height.
    img.Image noteImage({required bool headAtTop}) {
      final image = img.Image(width: 20, height: 80)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 18, y1: 0, x2: 19, y2: 79,
          color: img.ColorRgb8(0, 0, 0));
      final y1 = headAtTop ? 0 : 60;
      img.fillRect(image, x1: 0, y1: y1, x2: 19, y2: y1 + 19,
          color: img.ColorRgb8(0, 0, 0));
      return image;
    }

    const box = Rect.fromLTWH(0, 0, 20, 80);

    test('picks the bottom band for a stem-up note', () {
      final head =
          TfliteSymbolDetector.noteheadRect(noteImage(headAtTop: false), box);
      // Centred in the bottom 30% band (68), sized like a printed head.
      expect(head.center.dy, closeTo(68, 0.01));
      expect(head.height, closeTo(12.8, 0.01));
    });

    test('picks the top band for a stem-down note', () {
      final head =
          TfliteSymbolDetector.noteheadRect(noteImage(headAtTop: true), box);
      expect(head.center.dy, closeTo(12, 0.01));
    });
  });
}
