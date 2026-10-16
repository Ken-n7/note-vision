import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/genre_model.dart';

// The same notes as the `check` in note-vision-data/scripts/genre_train.py,
// so the app and the training script are held to the same numbers.
void main() {
  final score = Score(
    id: 's',
    title: 'Genre',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Treble',
        measures: [
          const Measure(
            number: 1,
            timeSignature: TimeSignature(beats: 3, beatType: 4),
            keySignature: KeySignature(fifths: 1),
            symbols: [Rest(duration: 6, type: 'half', dots: 1)], // dropped
          ),
          const Measure(
            number: 2,
            symbols: [
              Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
              Rest(duration: 1, type: 'eighth'),
              Note(step: 'G', octave: 4, duration: 2, type: 'quarter', dots: 1),
            ],
          ),
          const Measure(
            number: 3,
            timeSignature: TimeSignature(beats: 5, beatType: 4),
            symbols: [
              Note(step: 'G', octave: 5, duration: 8, type: 'whole'),
              Note(
                step: 'B',
                octave: 5,
                duration: 8,
                type: 'whole',
                isChordTone: true,
              ),
              Note(step: 'F', octave: 4, duration: 2, type: 'quarter'),
            ],
          ),
        ],
      ),
    ],
  );

  test('melody: pitch with key, top of a chord, place in bar, beats', () {
    expect(GenreModel.melody(score), [
      [60, 1.0, 0.0, 3],
      [-1, 0.5, 1 / 3, 3],
      [67, 1.5, 0.5, 3],
      [83, 4.0, 0.0, 5], // B5 over G5
      [66, 1.0, 0.8, 5], // F sharp from bar 1's key signature
    ]);
  });

  test('features match genre_train.py', () {
    final f = GenreModel.features(GenreModel.melody(score));
    expect(f[0][0], 0); // first note has no step
    expect(f[1][1], 1); // rest
    expect(f[2][0], closeTo(7 / 12, 1e-9)); // C4 -> G4
    expect(f[3][0], 1); // G4 -> B5 is clipped to an octave
    expect(f[4][0], -1); // B5 -> F#4 is clipped too
    expect(f[0][2], 0); // log2(1 quarter) / 2
    expect(f[3][2], 1); // log2(4) / 2
    expect(f[2][3], 0.5);
    expect(f[0][5], 1); // 3 beats
    expect(f[3][8], 1); // 5 beats: "other"
    final padded = GenreModel.pad(f);
    expect(padded.length, GenreModel.window);
    expect(padded.first, everyElement(0));
    expect(padded.last, f.last);
  });

  test(
    'melody reads the parts one after another, as a scan has a part per staff',
    () {
      final twoStaves = Score(
        id: 's2',
        title: 'Two staves',
        composer: '',
        parts: [score.parts.first, score.parts.first],
      );
      final one = GenreModel.melody(score);
      // The second staff opens with its bar of rest, kept as one rest between.
      expect(GenreModel.melody(twoStaves), [
        ...one,
        [-1, 3.0, 0.0, 3],
        ...one,
      ]);
    },
  );

  test('predict is null until the model is loaded', () {
    expect(GenreModel.predict(score), isNull);
  });
}
