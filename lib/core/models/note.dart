import 'score_review.dart';
import 'score_symbol.dart';
import 'note_beam.dart';
import 'articulation.dart';
import 'tuplet.dart';
import 'lyric.dart';

export 'note_beam.dart';
export 'articulation.dart';
export 'tuplet.dart';
export 'lyric.dart';

class Note extends ScoreSymbol {
  final String step; // C, D, E, F, G, A, B
  final int octave; // usually 0-9
  final int? alter; // -1 = flat, 1 = sharp, etc.
  final int duration; // effective divisions, including augmentation dots
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice; // optional
  final int? staff; // optional
  final bool _legacyBeamed;

  /// Numbered beam boundaries and hooks. Older scores use the boolean flag.
  final Map<int, BeamValue> beams;
  bool get beamed => _legacyBeamed || beams.containsKey(1);
  final int dots; // number of augmentation dots
  final bool isChordTone; // true when this note starts with the preceding note

  /// The detector's confidence for a scanned note; null when the note was
  /// typed, imported or edited, so an edited note no longer counts as unsure.
  final double? confidence;
  final String? reviewId;
  final SourceRegion? source;

  const Note({
    required this.step,
    required this.octave,
    this.alter,
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
    bool beamed = false,
    this.beams = const {},
    this.dots = 0,
    this.isChordTone = false,
    this.confidence,
    this.reviewId,
    this.source,
    this.tuplet,
    this.marks = const [],
    this.dynamicMark,
    this.lyrics = const [],
    this.grace,
    this.drum,
    this.notehead,
    this.string,
    this.fret,
    this.staffMove = 0,
  }) : _legacyBeamed = beamed;

  /// Cross-staff: drawn this many staves below (+) or above (−) its own,
  /// within the instrument, keeping its voice's time (MuseScore's staff
  /// move; MusicXML writes the other `<staff>`).
  final int staffMove;

  /// On a tablature staff: the string (1 is the highest) and fret written
  /// for this note. The pitch is what sounds.
  final int? string, fret;

  /// On a percussion staff, the kit piece as its General MIDI key (38 is
  /// the snare); [step] and [octave] then give only its staff position
  /// (MusicXML's display-step and display-octave).
  final int? drum;

  /// A MusicXML notehead other than the normal one: `x`, `circle-x`,
  /// `diamond`…
  final String? notehead;

  /// A grace note written before the next note: it takes no time in the bar
  /// and borrows its sound from a neighbour in playback.
  final Grace? grace;

  /// The tuplet this note belongs to, if any.
  final Tuplet? tuplet;

  /// Articulations, ornaments and fermatas on this note.
  final List<Articulation> marks;

  /// A dynamic starting at this note, named as MusicXML names it (p, mf,
  /// sfz…).
  final String? dynamicMark;

  final List<Lyric> lyrics;

  static const Object _keep = Object();

  /// This note with the given fields changed and every other field kept,
  /// so that adding a field to [Note] cannot be lost by a copy.
  Note copyWith({
    String? step,
    int? octave,
    Object? alter = _keep,
    int? duration,
    String? type,
    Object? voice = _keep,
    Object? staff = _keep,
    Map<int, BeamValue>? beams,
    bool? beamed,
    int? dots,
    bool? isChordTone,
    Object? confidence = _keep,
    Object? reviewId = _keep,
    Object? source = _keep,
    Object? tuplet = _keep,
    List<Articulation>? marks,
    Object? dynamicMark = _keep,
    List<Lyric>? lyrics,
    Object? grace = _keep,
    Object? drum = _keep,
    Object? notehead = _keep,
    Object? string = _keep,
    Object? fret = _keep,
    int? staffMove,
  }) => Note(
    staffMove: staffMove ?? this.staffMove,
    string: identical(string, _keep) ? this.string : string as int?,
    fret: identical(fret, _keep) ? this.fret : fret as int?,
    drum: identical(drum, _keep) ? this.drum : drum as int?,
    notehead: identical(notehead, _keep) ? this.notehead : notehead as String?,
    grace: identical(grace, _keep) ? this.grace : grace as Grace?,
    step: step ?? this.step,
    octave: octave ?? this.octave,
    alter: identical(alter, _keep) ? this.alter : alter as int?,
    duration: duration ?? this.duration,
    type: type ?? this.type,
    voice: identical(voice, _keep) ? this.voice : voice as int?,
    staff: identical(staff, _keep) ? this.staff : staff as int?,
    beamed: beamed ?? (beams == null && _legacyBeamed),
    beams: beams ?? this.beams,
    dots: dots ?? this.dots,
    isChordTone: isChordTone ?? this.isChordTone,
    confidence: identical(confidence, _keep)
        ? this.confidence
        : confidence as double?,
    reviewId: identical(reviewId, _keep) ? this.reviewId : reviewId as String?,
    source: identical(source, _keep) ? this.source : source as SourceRegion?,
    tuplet: identical(tuplet, _keep) ? this.tuplet : tuplet as Tuplet?,
    marks: marks ?? this.marks,
    lyrics: lyrics ?? this.lyrics,
    dynamicMark: identical(dynamicMark, _keep)
        ? this.dynamicMark
        : dynamicMark as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'note',
    'step': step,
    'octave': octave,
    if (alter != null) 'alter': alter,
    'duration': duration,
    'type': type,
    if (voice != null) 'voice': voice,
    if (staff != null) 'staff': staff,
    if (beamed) 'beamed': true,
    if (beams.isNotEmpty)
      'beams': {
        for (final entry in beams.entries) '${entry.key}': entry.value.xmlValue,
      },
    if (dots > 0) 'dots': dots,
    if (isChordTone) 'isChordTone': true,
    if (confidence != null) 'confidence': confidence,
    if (reviewId != null) 'reviewId': reviewId,
    if (source != null) 'source': source!.toJson(),
    if (tuplet != null) 'tuplet': tuplet!.toJson(),
    if (marks.isNotEmpty) 'marks': [for (final m in marks) m.name],
    if (dynamicMark != null) 'dynamic': dynamicMark,
    if (lyrics.isNotEmpty)
      'lyrics': [for (final lyric in lyrics) lyric.toJson()],
    if (grace != null) 'grace': grace!.name,
    if (drum != null) 'drum': drum,
    if (notehead != null) 'notehead': notehead,
    if (string != null) 'string': string,
    if (fret != null) 'fret': fret,
    if (staffMove != 0) 'staffMove': staffMove,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    tuplet: Tuplet.fromJson(json['tuplet']),
    marks: Articulation.listFromJson(json['marks']),
    dynamicMark: json['dynamic'] as String?,
    lyrics: Lyric.listFromJson(json['lyrics']),
    grace: Grace.values.where((g) => g.name == json['grace']).firstOrNull,
    drum: json['drum'] as int?,
    notehead: json['notehead'] as String?,
    string: json['string'] as int?,
    fret: json['fret'] as int?,
    staffMove: json['staffMove'] as int? ?? 0,
    step: json['step'] as String,
    octave: json['octave'] as int,
    alter: json['alter'] as int?,
    duration: json['duration'] as int,
    type: json['type'] as String,
    voice: json['voice'] as int?,
    staff: json['staff'] as int?,
    beamed: json['beamed'] as bool? ?? false,
    beams: _readBeams(json['beams']),
    dots: json['dots'] as int? ?? 0,
    isChordTone: json['isChordTone'] as bool? ?? false,
    confidence: (json['confidence'] as num?)?.toDouble(),
    reviewId: json['reviewId'] as String?,
    source: json['source'] == null
        ? null
        : SourceRegion.fromJson(
            Map<String, dynamic>.from(json['source'] as Map),
          ),
  );

  static Map<int, BeamValue> _readBeams(dynamic json) {
    if (json is! Map) return const {};
    final result = <int, BeamValue>{};
    for (final entry in json.entries) {
      final level = int.tryParse('${entry.key}');
      final value = BeamValue.parse('${entry.value}');
      if (level != null && level >= 1 && level <= 8 && value != null) {
        result[level] = value;
      }
    }
    return Map.unmodifiable(result);
  }

  Note withBeams(Map<int, BeamValue> values) =>
      copyWith(beams: Map.unmodifiable(values));

  /// The same note written as [step][octave] with accidental [alter].
  Note withPitch(String step, int octave, int? alter) =>
      copyWith(step: step, octave: octave, alter: alter);

  String get pitch {
    final accidental = switch (alter) {
      -2 => 'bb',
      -1 => 'b',
      1 => '#',
      2 => 'x',
      _ => '',
    };
    return '$step$accidental$octave';
  }

  @override
  String toString() =>
      'Note(pitch: $pitch, duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      '${beamed ? ', beamed: true' : ''}'
      '${dots > 0 ? ', dots: $dots' : ''}'
      '${isChordTone ? ', isChordTone: true' : ''}'
      ')';
}

/// How a grace note is played, as MuseScore Studio plays it. An
/// appoggiatura (no slash) takes its time from the start of its main note;
/// an acciaccatura (slashed) from the end of the note before.
enum Grace { appoggiatura, acciaccatura }
