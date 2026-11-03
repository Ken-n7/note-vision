import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';

Note engravingNote(
  String step, {
  String type = 'quarter',
  int octave = 4,
  int? alter,
  int voice = 1,
  bool chord = false,
  bool beamed = false,
  Grace? grace,
  List<Lyric> lyrics = const [],
}) => Note(
  step: step,
  octave: octave,
  type: type,
  duration: 2,
  alter: alter,
  voice: voice,
  isChordTone: chord,
  beamed: beamed,
  grace: grace,
  lyrics: lyrics,
);

Score engravingFixture() => Score(
  id: 'engraving-qa',
  title: 'Engraving QA',
  composer: 'Note Vision',
  parts: [
    Part(
      id: 'P1',
      name: 'Voice',
      measures: [
        Measure(
          number: 1,
          clef: const Clef(sign: 'G', line: 2),
          timeSignature: const TimeSignature(beats: 4, beatType: 4),
          symbols: [
            engravingNote('C'),
            engravingNote('D', type: 'eighth'),
            engravingNote('E', type: 'eighth'),
            engravingNote('G', type: 'half'),
          ],
        ),
        Measure(
          number: 2,
          symbols: [
            for (var i = 0; i < 16; i++)
              engravingNote(
                const ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C'][i % 8],
                octave: i % 8 == 7 ? 5 : 4,
                type: 'sixteenth',
                beamed: true,
              ),
          ],
        ),
        Measure(
          number: 3,
          symbols: [
            engravingNote('D', type: 'eighth', grace: Grace.acciaccatura),
            engravingNote('E', type: 'eighth', grace: Grace.acciaccatura),
            engravingNote('F', lyrics: const [Lyric(text: 'Beautiful')]),
            engravingNote('G', lyrics: const [Lyric(text: 'melodies')]),
            engravingNote(
              'A',
              type: 'half',
              lyrics: const [Lyric(text: 'sing')],
            ),
          ],
          annotations: const [
            ScoreAnnotation(kind: AnnotationKind.staffText, text: 'dolce'),
            ScoreAnnotation(kind: AnnotationKind.staffText, text: 'cantabile'),
            ScoreAnnotation(
              kind: AnnotationKind.chord,
              chord: ChordSymbol(root: 'C', kind: 'major-seventh'),
            ),
          ],
        ),
        Measure(
          number: 4,
          symbols: [
            engravingNote('C', type: 'half', alter: 1),
            engravingNote('D', type: 'half', alter: -1, chord: true),
            engravingNote('E', type: 'half', alter: 0, chord: true),
            engravingNote('F', type: 'half', alter: 1, chord: true),
            engravingNote('G', type: 'half'),
            engravingNote('B', type: 'half', chord: true),
            engravingNote('C', type: 'whole', voice: 2),
          ],
        ),
      ],
    ),
  ],
);
