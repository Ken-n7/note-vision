import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  const mapper = DetectionToScoreMapperService();

  group('DetectionToScoreMapperService.map', () {
    test('accepts mock detection input and builds measures, notes, and rests', () {
      const detection = DetectionResult(
        imageId: 'mock-detection',
        staffs: [
          DetectedStaff(
            id: 'staff-1',
            topY: 100,
            bottomY: 140,
            lineYs: [100, 110, 120, 130, 140],
          ),
        ],
        barlines: [DetectedBarline(x: 90, staffId: 'staff-1')],
        symbols: [
          DetectedSymbol(
            id: 'clef-1',
            type: 'clefG',
            x: 10,
            y: 92,
            width: 20,
            height: 48,
            confidence: 0.99,
          ),
          DetectedSymbol(
            id: 'head-1',
            type: 'noteheadBlack',
            x: 42,
            y: 136,
            width: 10,
            height: 8,
            confidence: 0.95,
          ),
          DetectedSymbol(
            id: 'stem-1',
            type: 'stem',
            x: 50,
            y: 108,
            width: 2,
            height: 28,
            confidence: 0.93,
          ),
          DetectedSymbol(
            id: 'rest-1',
            type: 'restQuarter',
            x: 108,
            y: 116,
            width: 8,
            height: 20,
            confidence: 0.88,
          ),
        ],
      );

      final result = mapper.map(detection);
      final part = result.score.parts.single;

      expect(result.errors, isEmpty);
      expect(result.score.title, isEmpty);
      expect(part.name, 'Detected Part');
      expect(part.measureCount, 2);
      expect(part.measures.first.clef?.sign, 'G');
      expect(part.measures.first.notes.single.type, 'quarter');
      expect(part.measures.first.notes.single.pitch, 'E4');
      expect(part.measures[1].rests.single.type, 'quarter');
      expect(result.confidenceSummary?.inputSymbolCount, 4);
      expect(result.confidenceSummary?.mappedSymbolCount, 2);
    });

    test('returns an empty score with warnings when no staff is detected', () {
      const detection = DetectionResult(
        imageId: 'no-staffs',
        symbols: [
          DetectedSymbol(id: 'rest-1', type: 'restQuarter', x: 12, y: 20),
        ],
      );

      final result = mapper.map(detection);

      expect(result.score.parts.single.measures.single.symbols, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('No staff detected'));
      expect(result.confidenceSummary?.mappedSymbolCount, 0);
    });

    test('returns a partial mapped score and warnings for unsupported symbols', () {
      const detection = DetectionResult(
        imageId: 'partial',
        staffs: [
          DetectedStaff(
            id: 'staff-1',
            topY: 100,
            bottomY: 140,
            lineYs: [100, 110, 120, 130, 140],
          ),
        ],
        symbols: [
          DetectedSymbol(
            id: 'head-1',
            type: 'noteheadBlack',
            x: 42,
            y: 136,
            width: 10,
            height: 8,
          ),
          DetectedSymbol(
            id: 'beam-1',
            type: 'beam',
            x: 60,
            y: 100,
            width: 24,
            height: 5,
          ),
        ],
      );

      final result = mapper.map(detection);

      expect(result.score.parts.single.measures.single.symbols, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((warning) => warning.contains('Unsupported symbol "beam"')),
        isTrue,
      );
      expect(
        result.warnings.any((warning) => warning.contains('Could not infer a supported note value')),
        isTrue,
      );
    });
  });
}
