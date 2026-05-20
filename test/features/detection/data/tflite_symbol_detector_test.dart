import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';

void main() {
  group('TfliteSymbolDetector confidence thresholds', () {
    test('returns per-class thresholds for small symbols', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.augmentationDot,
        ),
        0.55,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.accidentalNatural,
        ),
        0.60,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.ledgerLine,
        ),
        0.60,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.flag8thUp,
        ),
        0.65,
      );
    });

    test('falls back to the default threshold for structural classes', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.noteheadBlackOnLine,
        ),
        0.75,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.stem,
        ),
        0.75,
      );
      expect(
        TfliteSymbolDetector.confidenceThresholdFor(
          MusicSymbol.beam,
        ),
        0.75,
      );
    });

    test('falls back to the default threshold for unknown class names', () {
      expect(
        TfliteSymbolDetector.confidenceThresholdForName('madeUpSymbol'),
        0.75,
      );
    });
  });
}
