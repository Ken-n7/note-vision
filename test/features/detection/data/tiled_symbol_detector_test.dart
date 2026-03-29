import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/features/detection/data/tiled_symbol_detector.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';

class _FakeConstantDetector implements SymbolDetector {
  int calls = 0;

  @override
  Future<DetectionResult> detect(PreprocessedResult input) async {
    calls += 1;
    return const DetectionResult(
      symbols: [
        DetectedSymbol(
          id: 'notehead',
          type: 'noteheadBlack',
          x: 104,
          y: 104,
          width: 40,
          height: 40,
          confidence: 0.9,
        ),
      ],
    );
  }
}

void main() {
  group('TiledSymbolDetector', () {
    test('runs detector on each tile and remaps coordinates to full image', () async {
      final base = _FakeConstantDetector();
      final detector = TiledSymbolDetector(
        base,
        gridColumns: 2,
        gridRows: 2,
        overlapFraction: 0,
      );

      final image = img.Image(width: 416, height: 416);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final input = PreprocessedResult(
        bytes: Uint8List.fromList(img.encodePng(image)),
        width: 416,
        height: 416,
        scale: 1,
        padX: 0,
        padY: 0,
      );

      final result = await detector.detect(input);

      expect(base.calls, 4);
      expect(result.symbols.length, 4);

      final xs = result.symbols.map((s) => s.x.round()).toList()..sort();
      final ys = result.symbols.map((s) => s.y.round()).toList()..sort();

      expect(xs, [52, 52, 260, 260]);
      expect(ys, [52, 52, 260, 260]);
    });

    test('falls back to base detector when image decoding fails', () async {
      final base = _FakeConstantDetector();
      final detector = TiledSymbolDetector(base);

      final input = PreprocessedResult(
        bytes: Uint8List.fromList(const [0, 1, 2, 3]),
        width: 416,
        height: 416,
        scale: 1,
        padX: 0,
        padY: 0,
      );

      final result = await detector.detect(input);

      expect(base.calls, 1);
      expect(result.symbols.length, 1);
    });
  });
}
