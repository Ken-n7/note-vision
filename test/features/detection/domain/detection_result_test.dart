import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/music_symbol.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

void main() {
  group('DetectedSymbol', () {
    test('can be created from a music symbol bounding box', () {
      final symbol = DetectedSymbol.fromMusicSymbol(
        id: 'symbol-1',
        symbol: MusicSymbol.noteheadBlack,
        boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
        confidence: 0.91,
        metadata: const {'pitchHint': 'C4'},
      );

      expect(symbol.id, 'symbol-1');
      expect(symbol.type, 'noteheadBlack');
      expect(symbol.x, 10);
      expect(symbol.y, 20);
      expect(symbol.width, 30);
      expect(symbol.height, 40);
      expect(symbol.confidence, 0.91);
      expect(symbol.musicSymbol, MusicSymbol.noteheadBlack);
      expect(symbol.boundingBox, const Rect.fromLTWH(10, 20, 30, 40));
      expect(symbol.toJson()['metadata'], const {'pitchHint': 'C4'});
    });

    test(
      'maps coordinates back to original image space when size is known',
      () {
        const symbol = DetectedSymbol(
          id: 'symbol-2',
          type: 'stem',
          x: 30,
          y: 50,
          width: 12,
          height: 80,
        );

        expect(
          symbol.toOriginalCoordinates(scale: 2, padX: 10, padY: 20),
          const Rect.fromLTWH(10, 15, 6, 40),
        );
      },
    );

    test(
      'returns null helpers when symbol dimensions are missing or type is unknown',
      () {
        const symbol = DetectedSymbol(
          id: 'symbol-3',
          type: 'futureCustomSymbol',
          x: 5,
          y: 7,
        );

        expect(symbol.boundingBox, isNull);
        expect(
          symbol.toOriginalCoordinates(scale: 1, padX: 0, padY: 0),
          isNull,
        );
        expect(symbol.musicSymbol, isNull);
      },
    );
  });

  group('DetectionResult', () {
    test('represents staffs, barlines, and symbols together', () {
      const result = DetectionResult(
        imageId: 'image-001',
        staffs: [
          DetectedStaff(
            id: 'staff-1',
            topY: 100,
            bottomY: 140,
            lineYs: [100, 110, 120, 130, 140],
          ),
        ],
        barlines: [
          DetectedBarline(x: 64, staffId: 'staff-1'),
          DetectedBarline(x: 128),
        ],
        symbols: [
          DetectedSymbol(
            id: 'symbol-1',
            type: 'clefG',
            x: 18,
            y: 105,
            width: 22,
            height: 58,
            confidence: 0.98,
          ),
          DetectedSymbol(
            id: 'symbol-2',
            type: 'restQuarter',
            x: 92,
            y: 116,
            confidence: 0.87,
            metadata: {'measureIndex': 0},
          ),
        ],
      );

      expect(result.hasDetections, isTrue);
      expect(result.staffs.single.lineYs, [100, 110, 120, 130, 140]);
      expect(result.barlines.map((barline) => barline.staffId), [
        'staff-1',
        null,
      ]);
      expect(result.symbols.map((symbol) => symbol.type), [
        'clefG',
        'restQuarter',
      ]);
    });

    test('serializes and deserializes cleanly for future mock JSON', () {
      final original = DetectionResult(
        imageId: 'sample-image',
        staffs: const [
          DetectedStaff(
            id: 'staff-a',
            topY: 12.5,
            bottomY: 32.5,
            lineYs: [12.5, 17.5, 22.5, 27.5, 32.5],
          ),
        ],
        barlines: const [DetectedBarline(x: 44.5, staffId: 'staff-a')],
        symbols: const [
          DetectedSymbol(
            id: 'note-1',
            type: 'noteheadHalf',
            x: 48.0,
            y: 18.0,
            width: 10.0,
            height: 8.0,
            confidence: 0.88,
            metadata: {
              'voice': 1,
              'candidatePitches': ['A4', 'C5'],
            },
          ),
        ],
      );

      final encoded = jsonEncode(original.toJson());
      final decoded = DetectionResult.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded, original);
      expect(encoded, contains('"staffs"'));
      expect(encoded, contains('"barlines"'));
      expect(encoded, contains('"symbols"'));
    });

    test('debug output is informative and includes major sections', () {
      const result = DetectionResult(
        imageId: 'debug-image',
        staffs: [
          DetectedStaff(
            id: 'staff-debug',
            topY: 1,
            bottomY: 5,
            lineYs: [1, 2, 3, 4, 5],
          ),
        ],
        barlines: [DetectedBarline(x: 42)],
        symbols: [DetectedSymbol(id: 's1', type: 'timeSig', x: 12, y: 9)],
      );

      expect(result.toString(), contains('DetectionResult('));
      expect(result.toString(), contains('staffs'));
      expect(result.toString(), contains('barlines'));
      expect(result.toString(), contains('symbols'));
      expect(result.symbols.single.toString(), contains('DetectedSymbol('));
      expect(result.staffs.single.toString(), contains('DetectedStaff('));
      expect(result.barlines.single.toString(), contains('DetectedBarline('));
    });

    test('ScanResult exposes detection symbols and detection presence', () {
      final scanResult = ScanResult(
        preprocessed: PreprocessedResult(
          bytes: Uint8List.fromList(const [1, 2, 3]),
          width: 416,
          height: 416,
          scale: 1,
          padX: 0,
          padY: 0,
        ),
        detection: const DetectionResult(
          symbols: [DetectedSymbol(id: 's', type: 'flag8', x: 10, y: 10)],
        ),
      );

      expect(scanResult.hasDetections, isTrue);
      expect(scanResult.symbols.single.type, 'flag8');
    });
  });
}
