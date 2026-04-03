// Tests for the expanded reconstruction features introduced in ticket 59:
//  • Note-level accidentals (alter field)
//  • Beamed eighth notes
//  • rest8th / rest16th
//  • Bass-clef pitch calculation
//
// The existing Sprint 4 tests in detection_to_score_mapper_service_test.dart
// continue to exercise the core pipeline; these tests isolate the new behaviour.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  const mapper = DetectionToScoreMapperService();

  // Staff with 5 evenly-spaced lines (spacing = 10 px).
  // Treble bottom line (E4) sits at y=140; half-step spacing = 5 px.
  // Bass bottom line (G2) sits at y=140 with the same spacing.
  const staff = DetectedStaff(
    id: 'staff-1',
    topY: 100,
    bottomY: 140,
    lineYs: [100.0, 110.0, 120.0, 130.0, 140.0],
  );

  // Helper: a fully-specified symbol.
  DetectedSymbol sym({
    required String id,
    required String type,
    required double x,
    required double y,
    double width = 10,
    double height = 8,
  }) => DetectedSymbol(id: id, type: type, x: x, y: y, width: width, height: height);

  // ─────────────────────────────────────────────────────────────
  // ACCIDENTALS ON INDIVIDUAL NOTES
  // ─────────────────────────────────────────────────────────────
  //
  // Layout per test:
  //   gClef  x=10   → signature zone ends at first-note centre (x=55)
  //   note-1 x=50   → quarter B4 (treble, no accidental expected)
  //   stem-1 x=58
  //   <accidental> x=70   → body accidental targeting note-2
  //   note-2 x=88   → quarter G4
  //   stem-2 x=96
  //
  // The accidental (x=70..78) is after note-1 (centre 55) so it is NOT
  // in the signature zone and is matched to note-2 (nearest to its right).

  group('Note-level accidentals', () {
    DetectionResult buildAccidentalDetection(String accidentalType) =>
        DetectionResult(
          imageId: 'accidental-test',
          staffs: const [staff],
          symbols: [
            sym(id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44),
            sym(id: 'note-1', type: 'noteheadBlack', x: 50, y: 116),
            sym(id: 'stem-1', type: 'stem', x: 58, y: 88, width: 2, height: 32),
            sym(id: 'acc', type: accidentalType, x: 70, y: 103, width: 8, height: 18),
            sym(id: 'note-2', type: 'noteheadBlack', x: 88, y: 126),
            sym(id: 'stem-2', type: 'stem', x: 96, y: 98, width: 2, height: 32),
          ],
        );

    test('sharp before a notehead sets alter = 1', () {
      final result = mapper.map(buildAccidentalDetection('accidentalSharp'));
      final notes = result.score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes[0].alter, isNull); // note-1: no accidental
      expect(notes[1].alter, 1);      // note-2: sharp
      expect(notes[1].pitch, 'G#4');
    });

    test('flat before a notehead sets alter = -1', () {
      final result = mapper.map(buildAccidentalDetection('accidentalFlat'));
      final notes = result.score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes[0].alter, isNull);
      expect(notes[1].alter, -1);
      expect(notes[1].pitch, 'Gb4');
    });

    test('natural before a notehead sets alter = 0 (explicit natural)', () {
      final result = mapper.map(buildAccidentalDetection('accidentalNatural'));
      final notes = result.score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes[0].alter, isNull);
      expect(notes[1].alter, 0);
    });

    test('double sharp before a notehead sets alter = 2', () {
      final result = mapper.map(buildAccidentalDetection('accidentalDoubleSharp'));
      final notes = result.score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes[1].alter, 2);
      expect(notes[1].pitch, 'Gx4');
    });

    test('key-signature accidentals in the leading zone do NOT set note alter', () {
      // Two sharps before the first note → key signature (D major).
      // The body note should have no alter despite the key context.
      const detection = DetectionResult(
        imageId: 'key-sig-no-alter',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'sharp-1', type: 'accidentalSharp', x: 32, y: 101, width: 8, height: 18,
          ),
          DetectedSymbol(
            id: 'sharp-2', type: 'accidentalSharp', x: 42, y: 111, width: 8, height: 18,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 80, y: 116, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 88, y: 88, width: 2, height: 32,
          ),
        ],
      );

      final result = mapper.map(detection);
      final measure = result.score.parts.single.measures.single;

      expect(measure.keySignature?.fifths, 2); // D major
      expect(measure.notes.single.alter, isNull); // note itself has no explicit accidental
    });
  });

  // ─────────────────────────────────────────────────────────────
  // BEAMED EIGHTH NOTES
  // ─────────────────────────────────────────────────────────────
  //
  // A beam symbol whose X range overlaps a stem causes that notehead to be
  // reconstructed as an eighth note (instead of quarter).

  group('Beamed eighth notes', () {
    test('noteheadBlack + stem + beam → type: eighth, duration: 1', () {
      // Stem x=58..60; beam x=52..82 → horizontal overlap ✓
      const detection = DetectionResult(
        imageId: 'beam-single',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 116, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 82, width: 2, height: 38,
          ),
          DetectedSymbol(
            id: 'beam-1', type: 'beam', x: 52, y: 80, width: 30, height: 5,
          ),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.type, 'eighth');
      expect(note.duration, 1);
    });

    test('two noteheads under one beam are both reconstructed as eighth notes', () {
      // beam x=52..82 covers stem-1 (x=58..60) and stem-2 (x=74..76).
      const detection = DetectionResult(
        imageId: 'beam-pair',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 116, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 82, width: 2, height: 38,
          ),
          DetectedSymbol(
            id: 'note-2', type: 'noteheadBlack', x: 66, y: 126, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-2', type: 'stem', x: 74, y: 92, width: 2, height: 38,
          ),
          DetectedSymbol(
            id: 'beam-1', type: 'beam', x: 52, y: 80, width: 30, height: 5,
          ),
        ],
      );

      final result = mapper.map(detection);
      final notes = result.score.parts.single.measures.single.notes;

      expect(notes, hasLength(2));
      expect(notes.every((n) => n.type == 'eighth'), isTrue);
    });

    test('noteheadBlack + stem without beam or flag remains a quarter note', () {
      const detection = DetectionResult(
        imageId: 'no-beam-quarter',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 116, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 82, width: 2, height: 38,
          ),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.type, 'quarter');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // EIGHTH AND SIXTEENTH RESTS
  // ─────────────────────────────────────────────────────────────

  group('Expanded rest types', () {
    test('rest8th → Rest(type: eighth, duration: 1)', () {
      const detection = DetectionResult(
        imageId: 'rest8th',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'r1', type: 'rest8th', x: 60, y: 116, width: 8, height: 16,
          ),
        ],
      );

      final result = mapper.map(detection);
      final rest = result.score.parts.single.measures.single.rests.single;

      expect(rest.type, 'eighth');
      expect(rest.duration, 1);
    });

    test('rest16th → Rest(type: sixteenth, duration: 1)', () {
      const detection = DetectionResult(
        imageId: 'rest16th',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'gClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'r1', type: 'rest16th', x: 60, y: 116, width: 8, height: 16,
          ),
        ],
      );

      final result = mapper.map(detection);
      final rest = result.score.parts.single.measures.single.rests.single;

      expect(rest.type, 'sixteenth');
      expect(rest.duration, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // BASS CLEF PITCH RECONSTRUCTION
  // ─────────────────────────────────────────────────────────────
  //
  // Same staff geometry (spacing=10, bottomLineY=140).
  // Bass clef: bottom line (line 1) = G2, middle line (line 3) = D3.
  //
  // Offset = (140 − centerY) / 5   [half-step spacing = 5]
  // note at y=116 (h=8) → centre 120 → offset 4 → D3  (middle line)
  // note at y=136 (h=8) → centre 140 → offset 0 → G2  (bottom line)
  // note at y=126 (h=8) → centre 130 → offset 2 → B2  (line 2)

  group('Bass clef pitch reconstruction', () {
    test('fClef + notehead on middle line → D3', () {
      const detection = DetectionResult(
        imageId: 'bass-middle-line',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'fClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 116, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 88, width: 2, height: 32,
          ),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.step, 'D');
      expect(note.octave, 3);
      expect(note.pitch, 'D3');
    });

    test('fClef + notehead on bottom line → G2', () {
      const detection = DetectionResult(
        imageId: 'bass-bottom-line',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'fClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 136, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 108, width: 2, height: 32,
          ),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.step, 'G');
      expect(note.octave, 2);
      expect(note.pitch, 'G2');
    });

    test('fClef + notehead on line 2 → B2', () {
      const detection = DetectionResult(
        imageId: 'bass-line2',
        staffs: [staff],
        symbols: [
          DetectedSymbol(
            id: 'clef', type: 'fClef', x: 10, y: 92, width: 18, height: 44,
          ),
          DetectedSymbol(
            id: 'note-1', type: 'noteheadBlack', x: 50, y: 126, width: 10, height: 8,
          ),
          DetectedSymbol(
            id: 'stem-1', type: 'stem', x: 58, y: 98, width: 2, height: 32,
          ),
        ],
      );

      final result = mapper.map(detection);
      final note = result.score.parts.single.measures.single.notes.single;

      expect(note.step, 'B');
      expect(note.octave, 2);
      expect(note.pitch, 'B2');
    });
  });
}
