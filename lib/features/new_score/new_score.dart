import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note_value.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/drum_kit.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/tablature.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/transposer.dart';

/// One staff of a new score; [grand] adds a staff joined below it: bass, as
/// a piano has, or under a guitar's treble 8vb a linked TAB staff (MuseScore's
/// Guitar + Tablature). [lowerClef] specifies a second staff's clef,
/// including the two treble staves of an orchestral horn part.
class NewStaff {
  const NewStaff(
    this.name,
    this.clef, {
    this.grand = false,
    this.program,
    this.lowerClef,
    this.squareBracket = false,
    this.staffLines = 5,
    this.drumMap,
  });
  final String name;
  final Clef clef;
  final bool grand;
  final Clef? lowerClef;
  final bool squareBracket;
  final int staffLines;
  final List<DrumPiece>? drumMap;

  /// The GM sound when it is not the usual one for [name] (a jazz band's
  /// guitar is electric).
  final int? program;
}

const _treble = Clef(sign: 'G', line: 2);
const _treble8vb = Clef(sign: 'G', line: 2, octave: -1);
const _bass = Clef(sign: 'F', line: 4);
const _alto = Clef(sign: 'C', line: 3);
const _piano = NewStaff('Piano', _treble, grand: true);

/// A ready-made set of staves, as MuseScore Studio's templates group them.
class ScoreTemplate {
  const ScoreTemplate(this.group, this.name, this.staves);
  final String group, name;
  final List<NewStaff> staves;
}

/// The templates whose notation Note Vision can write.
/// Part names and clefs follow MuseScore Studio 4.7.5's
/// (`new_score_test.dart` compares them).
const scoreTemplates = <ScoreTemplate>[
  ScoreTemplate('General', 'Treble clef', [NewStaff('Piano', _treble)]),
  ScoreTemplate('General', 'Bass clef', [NewStaff('Piano', _bass)]),
  ScoreTemplate('General', 'Grand staff', [_piano]),
  ScoreTemplate('Choral', 'SATB', _satb),
  ScoreTemplate('Choral', 'SATB + Organ', [
    ..._satb,
    NewStaff('Organ', _treble, grand: true),
  ]),
  ScoreTemplate('Choral', 'SATB + Piano', [..._satb, _piano]),
  ScoreTemplate('Choral', 'Voice + Piano', [
    NewStaff('Voice', _treble),
    _piano,
  ]),
  ScoreTemplate('Chamber music', 'String quartet', [
    NewStaff('Violin I', _treble),
    NewStaff('Violin II', _treble),
    NewStaff('Viola', _alto),
    NewStaff('Violoncello', _bass),
  ]),
  ScoreTemplate('Chamber music', 'Wind quartet', [
    NewStaff('Flute', _treble),
    NewStaff('Oboe', _treble),
    NewStaff('Clarinet in Bb', _treble),
    NewStaff('Bassoon', _bass),
  ]),
  ScoreTemplate('Chamber music', 'Wind quintet', [
    NewStaff('Flute', _treble),
    NewStaff('Oboe', _treble),
    NewStaff('Clarinet in Bb', _treble),
    NewStaff('Horn in F', _treble),
    NewStaff('Bassoon', _bass),
  ]),
  ScoreTemplate('Chamber music', 'Saxophone quartet', [
    NewStaff('Soprano Saxophone', _treble),
    NewStaff('Alto Saxophone', _treble),
    NewStaff('Tenor Saxophone', _treble),
    NewStaff('Baritone Saxophone', _treble),
  ]),
  ScoreTemplate('Chamber music', 'Brass quartet', [
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Trombone', _bass),
    NewStaff('Tuba', _bass),
  ]),
  ScoreTemplate('Chamber music', 'Brass quintet', [
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Horn in F', _treble),
    NewStaff('Trombone', _bass),
    NewStaff('Tuba', _bass),
  ]),
  ScoreTemplate('Popular', 'Rock band', [
    NewStaff('Lead Vocals', _treble),
    NewStaff('Backing Vocals', _treble),
    NewStaff('Lead Guitar', _treble8vb),
    NewStaff('Rhythm Guitar', _treble8vb),
    NewStaff('Bass Guitar', _bass),
    NewStaff('Drum Kit', Clef.percussion),
  ]),
  ScoreTemplate('Solo', 'Guitar', [NewStaff('Classical Guitar', _treble8vb)]),
  ScoreTemplate('Solo', 'Guitar + tablature', [
    NewStaff('Guitar', _treble8vb, grand: true),
  ]),
  ScoreTemplate('Solo', 'Guitar tablature', [NewStaff('Guitar', Clef.tab)]),
  ScoreTemplate('Solo', 'Piano', [_piano]),
  ScoreTemplate('Jazz', 'Lead sheet', [NewStaff('Piano', _treble)]),
  ScoreTemplate('Jazz', 'Big band', [
    NewStaff('Alto Sax 1', _treble),
    NewStaff('Alto Sax 2', _treble),
    NewStaff('Tenor Sax 1', _treble),
    NewStaff('Tenor Sax 2', _treble),
    NewStaff('Bari Sax', _treble),
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Trumpet in Bb 3', _treble),
    NewStaff('Trumpet in Bb 4', _treble),
    NewStaff('Trombone 1', _bass),
    NewStaff('Trombone 2', _bass),
    NewStaff('Trombone 3', _bass),
    NewStaff('Trombone 4', _bass),
    NewStaff('Guitar', _treble8vb, program: 27),
    _piano,
    NewStaff('Acoustic Bass', _bass),
    NewStaff('Drum Kit', Clef.percussion),
  ]),
  ScoreTemplate('Jazz', 'Jazz combo', [
    NewStaff('Trumpet in Bb', _treble),
    NewStaff('Alto Sax', _treble),
    NewStaff('Tenor Sax', _treble),
    NewStaff('Trombone', _bass),
    NewStaff('Guitar', _treble8vb, program: 27),
    _piano,
    NewStaff('Acoustic Bass', _bass),
    NewStaff('Drum Kit', Clef.percussion),
  ]),
  ScoreTemplate('Band and percussion', 'Concert band', [
    NewStaff('Piccolo', _treble),
    NewStaff('Flute 1', _treble),
    NewStaff('Flute 2', _treble),
    NewStaff('Oboe 1', _treble),
    NewStaff('Oboe 2', _treble),
    NewStaff('Bassoon 1', _bass),
    NewStaff('Bassoon 2', _bass),
    NewStaff('Clarinet in Eb', _treble),
    NewStaff('Clarinet in Bb 1', _treble),
    NewStaff('Clarinet in Bb 2', _treble),
    NewStaff('Clarinet in Bb 3', _treble),
    NewStaff('Bass Clarinet', _treble),
    NewStaff('Alto Saxophone 1', _treble),
    NewStaff('Alto Saxophone 2', _treble),
    NewStaff('Tenor Saxophone', _treble),
    NewStaff('Baritone Saxophone', _treble),
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Trumpet in Bb 3', _treble),
    NewStaff('Horn in F 1 & 2', _treble),
    NewStaff('Horn in F 3 & 4', _treble),
    NewStaff('Trombone 1', _bass),
    NewStaff('Trombone 2', _bass),
    NewStaff('Trombone 3 &\nBass Trombone', _bass),
    NewStaff('Euphonium', _bass),
    NewStaff('Tuba', _bass),
    NewStaff('Double Bass', _bass),
    NewStaff('Timpani', _bass),
    NewStaff('Glockenspiel', _treble),
    NewStaff('Percussion 1', Clef.percussion),
    NewStaff('Percussion 2', Clef.percussion),
  ]),
  ScoreTemplate('Band and percussion', 'Small concert band', [
    NewStaff('Flute', _treble),
    NewStaff('Oboe', _treble),
    NewStaff('Bassoon', _bass),
    NewStaff('Clarinet in Bb 1', _treble),
    NewStaff('Clarinet in Bb 2', _treble),
    NewStaff('Bass Clarinet', _treble),
    NewStaff('Alto Saxophone', _treble),
    NewStaff('Tenor Saxophone', _treble),
    NewStaff('Baritone Saxophone', _treble),
    NewStaff('Horn in F', _treble),
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Trombone 1', _bass),
    NewStaff('Trombone 2\nBass Trombone', _bass),
    NewStaff('Euphonium', _bass),
    NewStaff('Tuba', _bass),
    NewStaff('Timpani', _bass),
    NewStaff('Glockenspiel', _treble),
    NewStaff('Percussion 1', Clef.percussion),
    NewStaff('Percussion 2', Clef.percussion),
  ]),
  ScoreTemplate('Orchestral', 'Classical orchestra', [
    NewStaff('Flutes', _treble),
    NewStaff('Oboes', _treble),
    NewStaff('Clarinets in Bb', _treble),
    NewStaff('Bassoons', _bass),
    NewStaff('Horns in F', _treble, lowerClef: _treble, squareBracket: true),
    NewStaff('Trumpets in Bb', _treble),
    NewStaff('Timpani', _bass),
    NewStaff('Violins 1', _treble),
    NewStaff('Violins 2', _treble),
    NewStaff('Violas', _alto),
    NewStaff('Violoncellos', _bass),
    NewStaff('Contrabasses', _bass),
  ]),
  ScoreTemplate('Orchestral', 'Symphony orchestra', [
    NewStaff('Flute 1', _treble),
    NewStaff('Flute 2', _treble),
    NewStaff('Oboe 1', _treble),
    NewStaff('Oboe 2', _treble),
    NewStaff('Clarinet in Bb 1', _treble),
    NewStaff('Clarinet in Bb 2', _treble),
    NewStaff('Bassoon 1', _bass),
    NewStaff('Bassoon 2', _bass),
    NewStaff('Horn in F 1 & 3', _treble),
    NewStaff('Horn in F 2 & 4', _treble),
    NewStaff('Trumpet in Bb 1', _treble),
    NewStaff('Trumpet in Bb 2', _treble),
    NewStaff('Trombone 1', _bass),
    NewStaff('Trombone 2', _bass),
    NewStaff('Tuba', _bass),
    NewStaff('Timpani', _bass),
    NewStaff(
      'Snare Drum',
      Clef.percussion,
      staffLines: 1,
      drumMap: orchestralSnare,
    ),
    NewStaff(
      'Bass Drum',
      Clef.percussion,
      staffLines: 1,
      drumMap: orchestralBassDrum,
    ),
    NewStaff(
      'Cymbals',
      Clef.percussion,
      staffLines: 1,
      drumMap: orchestralCymbals,
    ),
    NewStaff('Harp', _treble, grand: true),
    NewStaff('Violins 1', _treble),
    NewStaff('Violins 2', _treble),
    NewStaff('Violas', _alto),
    NewStaff('Violoncellos', _bass),
    NewStaff('Contrabasses', _bass),
  ]),
  ScoreTemplate('Orchestral', 'String orchestra', [
    NewStaff('Violins 1', _treble),
    NewStaff('Violins 2', _treble),
    NewStaff('Violas', _alto),
    NewStaff('Violoncellos', _bass),
    NewStaff('Contrabasses', _bass),
  ]),
];

const List<NewStaff> _satb = [
  NewStaff('Soprano', _treble),
  NewStaff('Alto', _treble),
  NewStaff('Tenor', _treble8vb),
  NewStaff('Bass', _bass),
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
    final playback = PartPlayback(
      program: staff.program ?? defaultProgramFor(staff.name),
    );
    final transposition = transpositionFor(staff.name);
    parts.add(
      Part(
        id: id,
        name: staff.name,
        playback: playback,
        staffLines: staff.staffLines,
        drumMap: staff.drumMap,
        transposition: transposition,
        tabTuning: staff.clef.isTab ? standardGuitarTuning : null,
        measures: measures(staff.clef, top: parts.isEmpty),
      ),
    );
    if (staff.grand || staff.lowerClef != null) {
      final tab = staff.lowerClef == null && staff.clef == _treble8vb;
      parts.add(
        Part(
          id: '$id-staff2',
          name: staff.name,
          staff: 2,
          playback: playback,
          transposition: transposition,
          squareBracket: staff.squareBracket,
          linked: tab,
          tabTuning: tab ? standardGuitarTuning : null,
          measures: measures(
            staff.lowerClef ?? (tab ? Clef.tab : _bass),
            top: false,
          ),
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
