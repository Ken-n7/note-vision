import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';

Note _n(String step, {int octave = 4, int? alter}) =>
    Note(step: step, octave: octave, alter: alter, duration: 2, type: 'quarter');

List<int> _midi(List<Measure> measures) => [
      for (final e in const PlaybackConverter().buildEvents(
        Score(
          id: 's',
          title: '',
          composer: '',
          parts: [Part(id: 'p', name: 'p', measures: measures)],
        ),
      ))
        e.midiNote,
    ];

void main() {
  test('notes take the key signature (D major: F and C are sharp)', () {
    expect(
      _midi([
        Measure(
          number: 1,
          keySignature: const KeySignature(fifths: 2),
          symbols: [_n('F'), _n('C', octave: 5), _n('G')],
        ),
        // The key holds in later measures that do not repeat it.
        Measure(number: 2, symbols: [_n('F')]),
      ]),
      [66, 73, 67, 66],
    );
  });

  test('flat keys lower B, E, A, D, G, C, F in that order', () {
    expect(
      _midi([
        Measure(
          number: 1,
          keySignature: const KeySignature(fifths: -3),
          symbols: [_n('B'), _n('E'), _n('A'), _n('D')],
        ),
      ]),
      [70, 63, 68, 62],
    );
  });

  test('a written accidental holds to the barline for that pitch only', () {
    expect(
      _midi([
        Measure(
          number: 1,
          keySignature: const KeySignature(fifths: 2),
          symbols: [
            _n('F', alter: 0), // natural sign
            _n('F'), // still natural
            _n('F', octave: 5), // other octave: key applies
          ],
        ),
        Measure(number: 2, symbols: [_n('F')]), // new bar: key again
      ]),
      [65, 65, 78, 66],
    );
  });
}
