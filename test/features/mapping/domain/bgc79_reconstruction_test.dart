// Tests for BGC-79: real-world reconstruction improvements.
//  • Barline fallback: MeasureGrouper splits by beat count when no barlines.
//  • Signature inheritance: ScoreBuilder carries clef/timeSig/keySig forward.
//  • Context-aware duration: stemless noteheadBlack infers whole or half from
//    remaining beats in the measure.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  const mapper = DetectionToScoreMapperService();

  const staff = DetectedStaff(
    id: 'staff-1',
    topY: 100,
    bottomY: 140,
    lineYs: [100.0, 110.0, 120.0, 130.0, 140.0],
  );

  DetectedSymbol sym({
    required String id,
    required String type,
    required double x,
    required double y,
    double width = 10,
    double height = 8,
  }) => DetectedSymbol(
    id: id,
    type: type,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // BARLINE FALLBACK
  // ─────────────────────────────────────────────────────────────────────────

  group('Barline fallback', () {
    test(
      '8 stemless noteheads with no barlines split into 2 measures of 4 (default 4/4)',
      () {
        final detection = DetectionResult(
          imageId: 'barline-fallback-8notes',
          staffs: const [staff],
          barlines: const [],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
            // 8 noteheads — no stems, so barline fallback groups by beat count
            for (int i = 0; i < 8; i++)
              sym(id: 'n$i', type: 'noteheadBlack', x: 50.0 + i * 12, y: 130),
          ],
        );

        final result = mapper.map(detection);
        final part = result.score.parts.single;

        expect(
          part.measures.length,
          2,
          reason: 'default 4/4 → 8 notes split into 2×4',
        );
        expect(part.measures[0].notes.length, 4);
        expect(part.measures[1].notes.length, 4);
      },
    );

    test(
      'timeSigCutCommon (2/2) causes 6 notes to split into 3 measures of 2',
      () {
        final detection = DetectionResult(
          imageId: 'barline-fallback-cut-common',
          staffs: const [staff],
          barlines: const [],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
            sym(
              id: 'ts',
              type: 'timeSigCutCommon',
              x: 28,
              y: 108,
              width: 12,
              height: 24,
            ),
            for (int i = 0; i < 6; i++)
              sym(id: 'n$i', type: 'noteheadBlack', x: 55.0 + i * 12, y: 130),
          ],
        );

        final result = mapper.map(detection);
        final part = result.score.parts.single;

        expect(part.measures.length, 3, reason: '2/2 → 6 notes split into 3×2');
        expect(part.measures[0].notes.length, 2);
        expect(part.measures[1].notes.length, 2);
        expect(part.measures[2].notes.length, 2);
      },
    );

    test(
      'signature symbols (clef) are placed in the first measure by the fallback',
      () {
        final detection = DetectionResult(
          imageId: 'barline-fallback-clef-placement',
          staffs: const [staff],
          barlines: const [],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
            for (int i = 0; i < 4; i++)
              sym(
                id: 'n$i',
                type: 'noteheadWhole',
                x: 50.0 + i * 12,
                y: 126,
                width: 12,
                height: 8,
              ),
          ],
        );

        final result = mapper.map(detection);
        final part = result.score.parts.single;

        // 4 whole notes → 1 measure (each whole consumes 0 quarter-beat-equivalent
        // in _splitByBeats, which counts symbol occurrences, not actual beat values)
        // All 4 notes stay in one measure; clef is inferred there.
        expect(part.measures.first.clef?.sign, 'G');
        expect(part.measures.first.notes.length, 4);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SIGNATURE INHERITANCE
  // ─────────────────────────────────────────────────────────────────────────

  group('Signature inheritance', () {
    // Three-measure layout with barlines:
    //   measure 1 (x < 80):  gClef + timeSig 4/4 + noteheadWhole at x=55
    //   measure 2 (80–130):  noteheadWhole at x=105 (no signature symbols)
    //   measure 3 (x > 130): noteheadWhole at x=150 (no signature symbols)

    late DetectionResult threeBarDetection;

    setUp(() {
      threeBarDetection = DetectionResult(
        imageId: 'signature-inheritance',
        staffs: const [staff],
        barlines: const [
          DetectedBarline(x: 80, staffId: 'staff-1'),
          DetectedBarline(x: 130, staffId: 'staff-1'),
        ],
        symbols: [
          // Measure 1 — has all signature symbols
          sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
          sym(
            id: 'ts-top',
            type: 'timeSig4',
            x: 30,
            y: 106,
            width: 10,
            height: 12,
          ),
          sym(
            id: 'ts-bot',
            type: 'timeSig4',
            x: 30,
            y: 120,
            width: 10,
            height: 12,
          ),
          sym(
            id: 'n1',
            type: 'noteheadWhole',
            x: 55,
            y: 126,
            width: 12,
            height: 8,
          ),
          // Measure 2 — no signature symbols
          sym(
            id: 'n2',
            type: 'noteheadWhole',
            x: 100,
            y: 126,
            width: 12,
            height: 8,
          ),
          // Measure 3 — no signature symbols
          sym(
            id: 'n3',
            type: 'noteheadWhole',
            x: 145,
            y: 126,
            width: 12,
            height: 8,
          ),
        ],
      );
    });

    test('clef is carried forward from measure 1 to measures 2 and 3', () {
      final result = mapper.map(threeBarDetection);
      final measures = result.score.parts.single.measures;

      expect(measures.length, 3);
      expect(measures[0].clef?.sign, 'G');
      expect(measures[1].clef?.sign, 'G', reason: 'inherited from measure 1');
      expect(measures[2].clef?.sign, 'G', reason: 'inherited from measure 1');
    });

    test('time signature 4/4 is carried forward to measures without one', () {
      final result = mapper.map(threeBarDetection);
      final measures = result.score.parts.single.measures;

      expect(measures[0].timeSignature?.beats, 4);
      expect(measures[0].timeSignature?.beatType, 4);
      expect(measures[1].timeSignature?.beats, 4, reason: 'inherited');
      expect(measures[1].timeSignature?.beatType, 4, reason: 'inherited');
      expect(measures[2].timeSignature?.beats, 4, reason: 'inherited');
    });

    test('key signature is carried forward to measures without one', () {
      final detection = DetectionResult(
        imageId: 'key-sig-inheritance',
        staffs: const [staff],
        barlines: const [
          DetectedBarline(x: 80, staffId: 'staff-1'),
          DetectedBarline(x: 130, staffId: 'staff-1'),
        ],
        symbols: [
          sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
          sym(
            id: 'ks',
            type: 'accidentalSharp',
            x: 28,
            y: 112,
            width: 8,
            height: 16,
          ),
          sym(
            id: 'n1',
            type: 'noteheadWhole',
            x: 55,
            y: 126,
            width: 12,
            height: 8,
          ),
          sym(
            id: 'n2',
            type: 'noteheadWhole',
            x: 100,
            y: 126,
            width: 12,
            height: 8,
          ),
          sym(
            id: 'n3',
            type: 'noteheadWhole',
            x: 145,
            y: 126,
            width: 12,
            height: 8,
          ),
        ],
      );

      final result = mapper.map(detection);
      final measures = result.score.parts.single.measures;

      expect(measures[0].keySignature?.fifths, 1, reason: 'G major (1 sharp)');
      expect(measures[1].keySignature?.fifths, 1, reason: 'inherited');
      expect(measures[2].keySignature?.fifths, 1, reason: 'inherited');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CONTEXT-AWARE DURATION FOR STEMLESS NOTEHEADS
  // ─────────────────────────────────────────────────────────────────────────

  group('Context-aware duration for stemless noteheadBlack', () {
    // Stem helper: places a stem that overlaps the notehead at (nx, 130).
    // The stem is at (nx+7, 106) with w=2, h=28 so it physically overlaps
    // the notehead in both X and Y as required by StemAssociator.
    DetectedSymbol stemFor(String id, double nx) =>
        sym(id: id, type: 'stem', x: nx + 7, y: 106, width: 2, height: 28);

    test('single stemless noteheadBlack is the only symbol → whole', () {
      final detection = DetectionResult(
        imageId: 'ctx-dur-whole',
        staffs: const [staff],
        barlines: const [],
        symbols: [
          sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
          sym(id: 'n1', type: 'noteheadBlack', x: 50, y: 130),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.type, 'whole');
      expect(note.duration, 4);
    });

    test(
      'stemless noteheadBlack as last symbol with 2 beats remaining → half',
      () {
        // Two stemmed quarter notes consume 2 beats, leaving 2 beats for the
        // final stemless notehead → half.
        final detection = DetectionResult(
          imageId: 'ctx-dur-half',
          staffs: const [staff],
          barlines: const [],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
            sym(id: 'n1', type: 'noteheadBlack', x: 50, y: 130),
            stemFor('s1', 50),
            sym(id: 'n2', type: 'noteheadBlack', x: 75, y: 130),
            stemFor('s2', 75),
            sym(id: 'n3', type: 'noteheadBlack', x: 100, y: 130), // stemless
          ],
        );

        final result = mapper.map(detection);
        final notes = result.score.parts.single.measures.single.notes;

        expect(notes.length, 3);
        expect(notes[0].type, 'quarter');
        expect(notes[1].type, 'quarter');
        expect(notes[2].type, 'half', reason: '2 beats remaining → half');
      },
    );

    test(
      'stemless noteheadBlack as last with only 1 beat remaining → quarter (fallback)',
      () {
        // Three stemmed quarter notes consume 3 beats; only 1 beat remains.
        // The stemless notehead falls back to quarter.
        final detection = DetectionResult(
          imageId: 'ctx-dur-quarter-fallback',
          staffs: const [staff],
          barlines: const [],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 5, y: 92, width: 20, height: 48),
            sym(id: 'n1', type: 'noteheadBlack', x: 50, y: 130),
            stemFor('s1', 50),
            sym(id: 'n2', type: 'noteheadBlack', x: 70, y: 130),
            stemFor('s2', 70),
            sym(id: 'n3', type: 'noteheadBlack', x: 90, y: 130),
            stemFor('s3', 90),
            sym(id: 'n4', type: 'noteheadBlack', x: 115, y: 130), // stemless
          ],
        );

        final result = mapper.map(detection);
        // With default 4/4 and 4 notes, the barline fallback keeps them all in
        // one measure (beat split triggers BEFORE adding note 5, which does not
        // exist here).
        final notes = result.score.parts.single.measures.single.notes;

        expect(notes.length, 4);
        expect(
          notes[3].type,
          'quarter',
          reason: 'only 1 beat remaining → quarter fallback',
        );
      },
    );
  });
}
