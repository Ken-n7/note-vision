import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  const mapper = DetectionToScoreMapperService();
  const singleStaff = DetectedStaff(
    id: 'staff-1',
    topY: 100,
    bottomY: 140,
    lineYs: [100, 110, 120, 130, 140],
  );

  group('DetectionToScoreMapperService.map', () {
    test('accepts mock detection input and builds measures, notes, and rests', () {
      const detection = DetectionResult(
        imageId: 'mock-detection',
        staffs: [singleStaff],
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

      test('recognizes whole notes without stems and keeps standalone rests', () {
      const detection = DetectionResult(
        imageId: 'whole-note-and-rest',
        staffs: [singleStaff],
        symbols: [
          DetectedSymbol(
            id: 'clef-1',
            type: 'gClef',
            x: 10,
            y: 95,
            width: 18,
            height: 42,
          ),
          DetectedSymbol(
            id: 'whole-1',
            type: 'noteheadWhole',
            x: 52,
            y: 126,
            width: 12,
            height: 8,
          ),
          DetectedSymbol(
            id: 'rest-1',
            type: 'restHalf',
            x: 88,
            y: 116,
            width: 10,
            height: 18,
          ),
        ],
      );

      final result = mapper.map(detection);
      final measure = result.score.parts.single.measures.single;

      expect(result.warnings, contains('No barlines detected; reconstructing a single measure.'));
      expect(measure.notes.single.type, 'whole');
      expect(measure.notes.single.pitch, 'G4');
      expect(measure.rests.single.type, 'half');
    });

    test('recognizes clef, key signature, and simple digit-based time signature', () {
      const detection = DetectionResult(
        imageId: 'signature-detection',
        staffs: [singleStaff],
        symbols: [
          DetectedSymbol(id: 'clef-1', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
          DetectedSymbol(id: 'sharp-1', type: 'accidentalSharp', x: 32, y: 101, width: 8, height: 18),
          DetectedSymbol(id: 'sharp-2', type: 'accidentalSharp', x: 41, y: 111, width: 8, height: 18),
          DetectedSymbol(id: 'time-top', type: 'timeSig4', x: 60, y: 102, width: 10, height: 14),
          DetectedSymbol(id: 'time-bottom', type: 'timeSig4', x: 60, y: 122, width: 10, height: 14),
          DetectedSymbol(id: 'head-1', type: 'noteheadBlack', x: 92, y: 136, width: 10, height: 8),
          DetectedSymbol(id: 'stem-1', type: 'stem', x: 100, y: 108, width: 2, height: 28),
        ],
      );

      final result = mapper.map(detection);
      final measure = result.score.parts.single.measures.single;

      expect(measure.clef?.sign, 'G');
      expect(measure.keySignature?.fifths, 2);
      expect(measure.timeSignature?.beats, 4);
      expect(measure.timeSignature?.beatType, 4);
      expect(measure.notes.single.type, 'quarter');
    });

    test('assigns symbols to the nearest staff and only maps the supported primary staff', () {
      const detection = DetectionResult(
        imageId: 'nearest-staff',
        staffs: [
          DetectedStaff(
            id: 'staff-1',
            topY: 100,
            bottomY: 140,
            lineYs: [100, 110, 120, 130, 140],
          ),
          DetectedStaff(
            id: 'staff-2',
            topY: 200,
            bottomY: 240,
            lineYs: [200, 210, 220, 230, 240],
          ),
        ],
        symbols: [
          DetectedSymbol(id: 'clef-1', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
          DetectedSymbol(id: 'head-1', type: 'noteheadBlack', x: 52, y: 136, width: 10, height: 8),
          DetectedSymbol(id: 'stem-1', type: 'stem', x: 60, y: 108, width: 2, height: 28),
          DetectedSymbol(id: 'rest-other', type: 'restQuarter', x: 54, y: 214, width: 10, height: 16),
        ],
      );

      final result = mapper.map(detection);
      final measure = result.score.parts.single.measures.single;

      expect(
        result.warnings,
        contains(
          'Multiple staffs detected, but Sprint 4 supports only a single staff. Using the best-matching staff assignments only.',
        ),
      );
      expect(measure.notes, hasLength(1));
      expect(measure.rests, isEmpty);
    });

    test('produces warnings instead of crashing for ambiguous noteheads and stray stems', () {
      const detection = DetectionResult(
        imageId: 'ambiguous',
        staffs: [singleStaff],
        symbols: [
          DetectedSymbol(id: 'clef-1', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
          DetectedSymbol(id: 'head-1', type: 'noteheadBlack', x: 52, y: 136, width: 10, height: 8),
          DetectedSymbol(id: 'stem-1', type: 'stem', x: 130, y: 108, width: 2, height: 28),
        ],
      );

      final result = mapper.map(detection);

      expect(result.score.parts.single.measures.single.symbols, isEmpty);
      expect(
        result.warnings.any((warning) => warning.contains('Could not confidently pair notehead head-1')),
        isTrue,
      );
      expect(
        result.warnings.any((warning) => warning.contains('Stem stem-1 could not be paired')),
        isTrue,
      );
      expect(
        result.warnings.any((warning) => warning.contains('Could not infer a supported note value from head-1')),
        isTrue,
      );
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
        staffs: [singleStaff],
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

    test('emits eighth notes when a flag is attached to the matched stem', () {
      const detection = DetectionResult(
        imageId: 'eighth-note',
        staffs: [singleStaff],
        symbols: [
          DetectedSymbol(id: 'clef-1', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
          DetectedSymbol(id: 'head-1', type: 'noteheadBlack', x: 52, y: 136, width: 10, height: 8),
          DetectedSymbol(id: 'stem-1', type: 'stem', x: 60, y: 108, width: 2, height: 28),
          DetectedSymbol(id: 'flag-1', type: 'flag8thUp', x: 61, y: 107, width: 8, height: 12),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note, isA<Note>());
      expect(note.type, 'eighth');
    });

    test('keeps symbols ordered from left to right within each measure', () {
      const detection = DetectionResult(
        imageId: 'order-check',
        staffs: [singleStaff],
        barlines: [DetectedBarline(x: 120, staffId: 'staff-1')],
        symbols: [
          DetectedSymbol(id: 'clef-1', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
          DetectedSymbol(id: 'rest-1', type: 'restQuarter', x: 100, y: 116, width: 8, height: 20),
          DetectedSymbol(id: 'head-1', type: 'noteheadWhole', x: 52, y: 126, width: 12, height: 8),
          DetectedSymbol(id: 'rest-2', type: 'restWhole', x: 140, y: 116, width: 8, height: 20),
        ],
      );

      final result = mapper.map(detection);
      final firstMeasureSymbols = result.score.parts.single.measures.first.symbols;
      final secondMeasureSymbols = result.score.parts.single.measures[1].symbols;

      expect(firstMeasureSymbols, hasLength(2));
      expect(firstMeasureSymbols.first, isA<Note>());
      expect(firstMeasureSymbols.last, isA<Rest>());
      expect(secondMeasureSymbols.single, isA<Rest>());
    });
  });
}