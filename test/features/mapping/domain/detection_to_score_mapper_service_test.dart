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

    DetectedSymbol symbol({
    required String id,
    required String type,
    required double x,
    required double y,
    double width = 10,
    double height = 8,
    double? confidence,
  }) {
    return DetectedSymbol(
      id: id,
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      confidence: confidence,
    );
  }

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

    test(
      'maps supported note and rest symbols with correct pitches, durations, and left-to-right ordering',
      () {
        final detection = DetectionResult(
          imageId: 'supported-symbols',
          staffs: const [singleStaff],
          symbols: [
            symbol(
              id: 'clef-1',
              type: 'clefG',
              x: 10,
              y: 92,
              width: 18,
              height: 44,
            ),
            symbol(
              id: 'rest-1',
              type: 'restHalf',
              x: 34,
              y: 116,
              width: 10,
              height: 18,
            ),
            symbol(
              id: 'whole-1',
              type: 'noteheadWhole',
              x: 58,
              y: 126,
              width: 12,
              height: 8,
            ),
            symbol(
              id: 'half-1',
              type: 'noteheadHalf',
              x: 92,
              y: 116,
              width: 10,
              height: 8,
            ),
            symbol(
              id: 'stem-half-1',
              type: 'stem',
              x: 100,
              y: 92,
              width: 2,
              height: 28,
            ),
            symbol(
              id: 'quarter-1',
              type: 'noteheadBlack',
              x: 124,
              y: 136,
              width: 10,
              height: 8,
            ),
            symbol(
              id: 'stem-quarter-1',
              type: 'stem',
              x: 132,
              y: 108,
              width: 2,
              height: 28,
            ),
            symbol(
              id: 'eighth-1',
              type: 'noteheadBlack',
              x: 156,
              y: 101,
              width: 10,
              height: 8,
            ),
            symbol(
              id: 'stem-eighth-1',
              type: 'stem',
              x: 164,
              y: 76,
              width: 2,
              height: 29,
            ),
            symbol(
              id: 'flag-eighth-1',
              type: 'flag8thUp',
              x: 165,
              y: 74,
              width: 8,
              height: 12,
            ),
            symbol(
              id: 'rest-2',
              type: 'restWhole',
              x: 190,
              y: 116,
              width: 10,
              height: 18,
            ),
          ],
        );

        final result = mapper.map(detection);
        final measure = result.score.parts.single.measures.single;
        final notes = measure.notes;
        final rests = measure.rests;

        expect(result.errors, isEmpty);
        expect(notes.map((note) => note.pitch).toList(), ['G4', 'B4', 'E4', 'E5']);
        expect(notes.map((note) => note.type).toList(), ['whole', 'half', 'quarter', 'eighth']);
        expect(rests.map((rest) => rest.type).toList(), ['half', 'whole']);
        expect(
          measure.symbols.map((symbol) => symbol.toString()).toList(),
          [
            'Rest(duration: 2, type: half, staff: 1)',
            'Note(pitch: G4, duration: 4, type: whole, staff: 1)',
            'Note(pitch: B4, duration: 2, type: half, staff: 1)',
            'Note(pitch: E4, duration: 1, type: quarter, staff: 1)',
            'Note(pitch: E5, duration: 1, type: eighth, staff: 1)',
            'Rest(duration: 4, type: whole, staff: 1)',
          ],
        );
      },
    );

    test('keeps an active treble clef across measures when later measures omit the clef symbol', () {
      final detection = DetectionResult(
        imageId: 'clef-carry-over',
        staffs: const [singleStaff],
        barlines: const [DetectedBarline(x: 120, staffId: 'staff-1')],
        symbols: [
          symbol(
            id: 'clef-1',
            type: 'gClef',
            x: 10,
            y: 92,
            width: 18,
            height: 44,
          ),
          symbol(
            id: 'head-1',
            type: 'noteheadBlack',
            x: 52,
            y: 136,
            width: 10,
            height: 8,
          ),
          symbol(
            id: 'stem-1',
            type: 'stem',
            x: 60,
            y: 108,
            width: 2,
            height: 28,
          ),
          symbol(
            id: 'head-2',
            type: 'noteheadHalf',
            x: 142,
            y: 116,
            width: 10,
            height: 8,
          ),
          symbol(
            id: 'stem-2',
            type: 'stem',
            x: 150,
            y: 90,
            width: 2,
            height: 30,
          ),
        ],
      );

      final result = mapper.map(detection);
      final measures = result.score.parts.single.measures;

      expect(measures.first.notes.single.pitch, 'E4');
      expect(measures[1].clef?.sign, 'G');
      expect(measures[1].notes.single.pitch, 'B4');
      expect(
        result.warnings.where((warning) => warning.contains('No supported treble clef detected')),
        isEmpty,
      );
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

    test('returns stable results across repeated mapping runs in one session', () {
      const detection = DetectionResult(
        imageId: 'repeatable-run',
        staffs: [singleStaff],
        barlines: [DetectedBarline(x: 90, staffId: 'staff-1')],
        symbols: [
          DetectedSymbol(
            id: 'clef-1',
            type: 'gClef',
            x: 10,
            y: 92,
            width: 18,
            height: 44,
          ),
          DetectedSymbol(
            id: 'head-1',
            type: 'noteheadBlack',
            x: 42,
            y: 136,
            width: 10,
            height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1',
            type: 'stem',
            x: 50,
            y: 108,
            width: 2,
            height: 28,
          ),
          DetectedSymbol(
            id: 'rest-1',
            type: 'restQuarter',
            x: 108,
            y: 116,
            width: 8,
            height: 20,
          ),
        ],
      );

      final first = mapper.map(detection);
      final second = mapper.map(detection);
      final third = mapper.map(detection);

      expect(second.score.toString(), first.score.toString());
      expect(third.score.toString(), first.score.toString());
      expect(second.warnings, first.warnings);
      expect(third.warnings, first.warnings);
      expect(second.errors, first.errors);
      expect(third.errors, first.errors);
      expect(
        second.confidenceSummary?.inputSymbolCount,
        first.confidenceSummary?.inputSymbolCount,
      );
      expect(
        third.confidenceSummary?.inputSymbolCount,
        first.confidenceSummary?.inputSymbolCount,
      );
      expect(
        second.confidenceSummary?.mappedSymbolCount,
        first.confidenceSummary?.mappedSymbolCount,
      );
      expect(
        third.confidenceSummary?.mappedSymbolCount,
        first.confidenceSummary?.mappedSymbolCount,
      );
      expect(
        second.confidenceSummary?.droppedSymbolCount,
        first.confidenceSummary?.droppedSymbolCount,
      );
      expect(
        third.confidenceSummary?.droppedSymbolCount,
        first.confidenceSummary?.droppedSymbolCount,
      );
      expect(
        second.confidenceSummary?.averageDetectionConfidence,
        first.confidenceSummary?.averageDetectionConfidence,
      );
      expect(
        third.confidenceSummary?.averageDetectionConfidence,
        first.confidenceSummary?.averageDetectionConfidence,
      );
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

    test('skips notes when no treble clef is available for pitch reconstruction', () {
      final detection = DetectionResult(
        imageId: 'missing-clef',
        staffs: const [singleStaff],
        symbols: [
          symbol(
            id: 'head-1',
            type: 'noteheadBlack',
            x: 42,
            y: 136,
            width: 10,
            height: 8,
          ),
          symbol(
            id: 'stem-1',
            type: 'stem',
            x: 50,
            y: 108,
            width: 2,
            height: 28,
          ),
        ],
      );

      final result = mapper.map(detection);

      expect(result.score.parts.single.measures.single.notes, isEmpty);
      expect(
        result.warnings.any(
          (warning) => warning.contains('Could not infer a supported treble-clef pitch'),
        ),
        isTrue,
      );
      expect(
        result.warnings.any(
          (warning) => warning.contains(
            'No supported treble clef detected; pitch reconstruction is unsupported for this measure.',
          ),
        ),
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