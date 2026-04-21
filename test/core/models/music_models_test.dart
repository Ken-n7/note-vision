import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';

void main() {
  group('Note', () {
    test('pitch maps accidental values correctly', () {
      final natural = Note(step: 'C', octave: 4, duration: 1, type: 'quarter');
      final flat = Note(
        step: 'D',
        octave: 5,
        alter: -1,
        duration: 1,
        type: 'quarter',
      );
      final doubleFlat = Note(
        step: 'E',
        octave: 3,
        alter: -2,
        duration: 1,
        type: 'quarter',
      );
      final sharp = Note(
        step: 'F',
        octave: 4,
        alter: 1,
        duration: 1,
        type: 'quarter',
      );
      final doubleSharp = Note(
        step: 'G',
        octave: 2,
        alter: 2,
        duration: 1,
        type: 'quarter',
      );
      final unknownAlter = Note(
        step: 'A',
        octave: 4,
        alter: 99,
        duration: 1,
        type: 'quarter',
      );

      expect(natural.pitch, 'C4');
      expect(flat.pitch, 'Db5');
      expect(doubleFlat.pitch, 'Ebb3');
      expect(sharp.pitch, 'F#4');
      expect(doubleSharp.pitch, 'Gx2');
      expect(unknownAlter.pitch, 'A4');
    });

    test('toString includes optional voice and staff only when present', () {
      const withVoiceAndStaff = Note(
        step: 'C',
        octave: 4,
        duration: 4,
        type: 'quarter',
        voice: 2,
        staff: 1,
      );
      const withoutOptional = Note(
        step: 'D',
        octave: 4,
        duration: 2,
        type: 'eighth',
      );

      expect(withVoiceAndStaff.toString(), contains('voice: 2'));
      expect(withVoiceAndStaff.toString(), contains('staff: 1'));
      expect(withoutOptional.toString(), isNot(contains('voice:')));
      expect(withoutOptional.toString(), isNot(contains('staff:')));
    });
  });

  group('KeySignature', () {
    test('maps known fifth values to expected key names', () {
      expect(const KeySignature(fifths: -1).name, 'F major');
      expect(const KeySignature(fifths: 0).name, 'C major');
      expect(const KeySignature(fifths: 2).name, 'D major');
      expect(const KeySignature(fifths: 7).name, 'C# major');
    });

    test('returns fallback for unknown fifth value', () {
      expect(const KeySignature(fifths: 9).name, 'Unknown key');
      expect(const KeySignature(fifths: -9).name, 'Unknown key');
    });
  });

  group('Measure', () {
    test('notes and rests getters filter symbols by type', () {
      const measure = Measure(
        number: 1,
        symbols: [
          Clef(sign: 'G', line: 2),
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
          Rest(duration: 1, type: 'quarter'),
          Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
        ],
      );

      expect(measure.symbolCount, 4);
      expect(measure.notes.length, 2);
      expect(measure.rests.length, 1);
      expect(measure.notes.map((note) => note.pitch), ['C4', 'E4']);
      expect(measure.rests.map((rest) => rest.type), ['quarter']);
    });
  });

  group('Part and Score aggregates', () {
    test('measureCount, partCount, and totalMeasures are computed correctly', () {
      const part1 = Part(
        id: 'p1',
        name: 'Piano RH',
        measures: [
          Measure(number: 1, symbols: []),
          Measure(number: 2, symbols: []),
        ],
      );

      const part2 = Part(
        id: 'p2',
        name: 'Piano LH',
        measures: [
          Measure(number: 1, symbols: []),
        ],
      );

      const score = Score(
        id: 's1',
        title: 'Etude',
        composer: 'Composer',
        parts: [part1, part2],
      );

      expect(part1.measureCount, 2);
      expect(part2.measureCount, 1);
      expect(score.partCount, 2);
      expect(score.totalMeasures, 3);
    });
  });

  group('Simple model toString smoke checks', () {
    test('clef, rest, and time signature toString are stable and informative', () {
      expect(const Clef(sign: 'F', line: 4).toString(), 'Clef(sign: F, line: 4)');
      expect(
        const Rest(duration: 2, type: 'half', voice: 1, staff: 2).toString(),
        'Rest(duration: 2, type: half, voice: 1, staff: 2)',
      );
      expect(
        const TimeSignature(beats: 3, beatType: 4).toString(),
        'TimeSignature(3/4)',
      );
    });
  });
}
