import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/tablature.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/transposer.dart';

/// One staff of a new score; [grand] adds a bass staff joined below it, as
/// a piano has.
typedef NewStaff = ({String name, Clef clef, bool grand});

const _treble = Clef(sign: 'G', line: 2);
const _treble8vb = Clef(sign: 'G', line: 2, octave: -1);
const _bass = Clef(sign: 'F', line: 4);
const _alto = Clef(sign: 'C', line: 3);
const NewStaff _piano = (name: 'Piano', clef: _treble, grand: true);

/// A ready-made set of staves, as MuseScore Studio's templates group them.
class ScoreTemplate {
  const ScoreTemplate(this.group, this.name, this.staves);
  final String group, name;
  final List<NewStaff> staves;
}

/// The templates whose notation Note Vision can write: no tablature or
/// orchestral percussion yet. Part names and clefs follow
/// MuseScore Studio 4.7.5's (`new_score_test.dart` compares them).
const scoreTemplates = <ScoreTemplate>[
  ScoreTemplate('General', 'Treble clef', [
    (name: 'Piano', clef: _treble, grand: false),
  ]),
  ScoreTemplate('General', 'Bass clef', [
    (name: 'Piano', clef: _bass, grand: false),
  ]),
  ScoreTemplate('General', 'Grand staff', [_piano]),
  ScoreTemplate('Choral', 'SATB', _satb),
  ScoreTemplate('Choral', 'SATB + Piano', [..._satb, _piano]),
  ScoreTemplate('Choral', 'Voice + Piano', [
    (name: 'Voice', clef: _treble, grand: false),
    _piano,
  ]),
  ScoreTemplate('Chamber music', 'String quartet', [
    (name: 'Violin I', clef: _treble, grand: false),
    (name: 'Violin II', clef: _treble, grand: false),
    (name: 'Viola', clef: _alto, grand: false),
    (name: 'Violoncello', clef: _bass, grand: false),
  ]),
  ScoreTemplate('Chamber music', 'Wind quartet', [
    (name: 'Flute', clef: _treble, grand: false),
    (name: 'Oboe', clef: _treble, grand: false),
    (name: 'Clarinet in Bb', clef: _treble, grand: false),
    (name: 'Bassoon', clef: _bass, grand: false),
  ]),
  ScoreTemplate('Chamber music', 'Wind quintet', [
    (name: 'Flute', clef: _treble, grand: false),
    (name: 'Oboe', clef: _treble, grand: false),
    (name: 'Clarinet in Bb', clef: _treble, grand: false),
    (name: 'Horn in F', clef: _treble, grand: false),
    (name: 'Bassoon', clef: _bass, grand: false),
  ]),
  ScoreTemplate('Chamber music', 'Saxophone quartet', [
    (name: 'Soprano Saxophone', clef: _treble, grand: false),
    (name: 'Alto Saxophone', clef: _treble, grand: false),
    (name: 'Tenor Saxophone', clef: _treble, grand: false),
    (name: 'Baritone Saxophone', clef: _treble, grand: false),
  ]),
  ScoreTemplate('Chamber music', 'Brass quartet', [
    (name: 'Trumpet in Bb 1', clef: _treble, grand: false),
    (name: 'Trumpet in Bb 2', clef: _treble, grand: false),
    (name: 'Trombone', clef: _bass, grand: false),
    (name: 'Tuba', clef: _bass, grand: false),
  ]),
  ScoreTemplate('Chamber music', 'Brass quintet', [
    (name: 'Trumpet in Bb 1', clef: _treble, grand: false),
    (name: 'Trumpet in Bb 2', clef: _treble, grand: false),
    (name: 'Horn in F', clef: _treble, grand: false),
    (name: 'Trombone', clef: _bass, grand: false),
    (name: 'Tuba', clef: _bass, grand: false),
  ]),
  ScoreTemplate('Popular', 'Rock band', [
    (name: 'Lead Vocals', clef: _treble, grand: false),
    (name: 'Backing Vocals', clef: _treble, grand: false),
    (name: 'Lead Guitar', clef: _treble8vb, grand: false),
    (name: 'Rhythm Guitar', clef: _treble8vb, grand: false),
    (name: 'Bass Guitar', clef: _bass, grand: false),
    (name: 'Drum Kit', clef: Clef.percussion, grand: false),
  ]),
  ScoreTemplate('Solo', 'Guitar', [
    (name: 'Classical Guitar', clef: _treble8vb, grand: false),
  ]),
  ScoreTemplate('Solo', 'Guitar tablature', [
    (name: 'Guitar', clef: Clef.tab, grand: false),
  ]),
  ScoreTemplate('Solo', 'Piano', [_piano]),
  ScoreTemplate('Jazz', 'Lead sheet', [
    (name: 'Piano', clef: _treble, grand: false),
  ]),
];

const List<NewStaff> _satb = [
  (name: 'Soprano', clef: _treble, grand: false),
  (name: 'Alto', clef: _treble, grand: false),
  (name: 'Tenor', clef: _treble8vb, grand: false),
  (name: 'Bass', clef: _bass, grand: false),
];

/// What MuseScore Studio's New Score dialog asks for.
class NewScoreOptions {
  const NewScoreOptions({
    required this.staves,
    this.title = '',
    this.composer = '',
    this.fifths = 0,
    this.time = const TimeSignature(beats: 4, beatType: 4),
    this.bars = 32,
    this.pickupBeats = 0,
    this.tempo,
  });

  final List<NewStaff> staves;
  final String title, composer;
  final int fifths;
  final TimeSignature time;

  /// Full bars, not counting a pickup.
  final int bars;

  /// Beats (of [time]'s beat type) in a pickup bar; 0 for none.
  final int pickupBeats;

  /// A metronome mark in [tempoUnit]s per minute; null for none.
  final double? tempo;

  /// The beat a metronome mark counts: a dotted quarter in compound time, a
  /// half in 2/2, else a quarter.
  (String, int) get tempoUnit => time.beatType == 8 && time.beats % 3 == 0
      ? ('quarter', 1)
      : time.beatType == 2
      ? ('half', 0)
      : ('quarter', 0);

  /// Pickup lengths one rest can fill: 1 to beats − 1 beats.
  List<int> get pickupChoices => [
    for (var n = 1; n < time.beats; n++)
      if (valueForQuarters(n * 4 / time.beatType) != null) n,
  ];
}

/// An empty score: [o]'s staves, each with [o.bars] empty bars after an
/// optional pickup (a rest of its length, left out of the bar count), the
/// key, meter and an optional metronome mark at the start. [o.fifths] is the
/// concert key: transposing instruments are written in their own keys.
Score buildNewScore(NewScoreOptions o, {String? id}) {
  final pickup = o.pickupBeats > 0
      ? valueForQuarters(o.pickupBeats * 4 / o.time.beatType)
      : null;
  final key = KeySignature(fifths: o.fifths);
  final tempo = o.tempo == null
      ? null
      : ScoreAnnotation(
          kind: AnnotationKind.tempo,
          tempo: o.tempo! * quarterLength(o.tempoUnit.$1, o.tempoUnit.$2, 0),
          perMinute: o.tempo,
          beatUnit: o.tempoUnit.$1,
          beatDots: o.tempoUnit.$2,
        );
  List<Measure> measures(Clef clef, {required bool top}) {
    final first = <Measure>[
      if (pickup case (final type, final dots))
        Measure(
          number: 0,
          implicit: true,
          symbols: [
            Rest(
              duration: (o.pickupBeats * 8 / o.time.beatType).round(),
              type: type,
              dots: dots,
            ),
          ],
        ),
      for (var i = 0; i < o.bars; i++)
        Measure(number: i + 1, symbols: const []),
    ];
    return [
      first.first.copyWith(
        clef: clef,
        keySignature: key,
        timeSignature: o.time,
        annotations: top && tempo != null ? [tempo] : null,
      ),
      ...first.skip(1),
    ];
  }

  final parts = <Part>[];
  for (final staff in o.staves) {
    final id = 'P${parts.length + 1}';
    final playback = PartPlayback(program: defaultProgramFor(staff.name));
    parts.add(
      Part(
        id: id,
        name: staff.name,
        playback: playback,
        transposition: transpositionFor(staff.name),
        tabTuning: staff.clef.isTab ? standardGuitarTuning : null,
        measures: measures(staff.clef, top: parts.isEmpty),
      ),
    );
    if (staff.grand) {
      parts.add(
        Part(
          id: '$id-staff2',
          name: staff.name,
          staff: 2,
          playback: playback,
          measures: measures(_bass, top: false),
        ),
      );
    }
  }
  // Built in concert pitch, then written as the players read it.
  return const Transposer().concertPitch(
    Score(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: o.title.isEmpty ? 'Untitled' : o.title,
      composer: o.composer,
      parts: parts,
      playbackLayout: ScorePlaybackLayout.simultaneousParts,
      concertPitch: true,
    ),
    false,
  );
}
