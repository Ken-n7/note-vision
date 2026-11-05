import 'measure.dart';
import 'part_playback.dart';
import 'transposition.dart';
import 'drum_kit.dart';

export 'transposition.dart';

class Part {
  final String id;
  final String name;
  final List<Measure> measures;
  final PartPlayback playback;

  /// This part's staff within its instrument. A part with staff 2 or more is
  /// a further staff of the part before it (a piano's left hand): every
  /// editing tool works per staff, and MusicXML import splits `<staves>`
  /// into such parts and export merges them back into one `<part>`.
  final int staff;

  const Part({
    required this.id,
    required this.name,
    required this.measures,
    this.staff = 1,
    this.playback = const PartPlayback(),
    this.transposition,
    this.tabTuning,
    this.linked = false,
    this.squareBracket = false,
    this.staffLines = 5,
    this.drumMap,
  });

  /// A linked staff (MuseScore's Guitar + Tablature): this staff shows the
  /// same music as the staff before it, an edit to either is copied to the
  /// other (`syncLinkedStaves`), and only the staff before it plays.
  final bool linked;

  /// A further staff of the instrument above, joined by a square bracket
  /// instead of a piano brace (e.g. two orchestral horn staves).
  final bool squareBracket;

  /// Five lines normally; orchestral percussion uses one middle line.
  final int staffLines;
  final List<DrumPiece>? drumMap;
  List<DrumPiece> get drums => drumMap?.isNotEmpty == true ? drumMap! : drumKit;
  bool get singleLine => isPercussion && staffLines == 1;

  /// A tablature staff's open strings as MIDI notes, lowest first.
  final List<int>? tabTuning;

  /// A tablature staff: its first clef is a TAB clef.
  bool get isTab =>
      measures.map((m) => m.clef).nonNulls.firstOrNull?.isTab ?? false;

  /// A transposing instrument's interval from written to sounding pitch.
  /// Notes and key signatures are stored as written, unless the score is in
  /// concert pitch ([Score.concertPitch]); playback sounds them.
  final Transposition? transposition;

  /// A drum staff: its first clef is a percussion clef.
  bool get isPercussion =>
      measures.map((m) => m.clef).nonNulls.firstOrNull?.isPercussion ?? false;

  /// Whether this part continues the instrument of the part before it.
  bool get joinsPrevious => staff > 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'measures': measures.map((m) => m.toJson()).toList(),
    if (staff > 1) 'staff': staff,
    if (playback != const PartPlayback()) 'playback': playback.toJson(),
    if (transposition != null) 'transposition': transposition!.toJson(),
    if (tabTuning != null) 'tabTuning': tabTuning,
    if (linked) 'linked': true,
    if (squareBracket) 'squareBracket': true,
    if (staffLines != 5) 'staffLines': staffLines,
    if (drumMap != null) 'drumMap': [for (final d in drumMap!) d.toJson()],
  };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
    id: json['id'] as String,
    name: json['name'] as String,
    staff: json['staff'] as int? ?? 1,
    playback: PartPlayback.fromJson(
      json['playback'] as Map<String, dynamic>? ?? {},
    ),
    transposition: Transposition.fromJson(json['transposition']),
    tabTuning: (json['tabTuning'] as List?)?.cast<int>(),
    linked: json['linked'] as bool? ?? false,
    squareBracket: json['squareBracket'] as bool? ?? false,
    staffLines: json['staffLines'] as int? ?? 5,
    drumMap: (json['drumMap'] as List?)
        ?.map((d) => DrumPiece.fromJson(d as Map<String, dynamic>))
        .toList(),
    measures: (json['measures'] as List<dynamic>)
        .map((m) => Measure.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  Part copyWith({
    String? id,
    String? name,
    int? staff,
    List<Measure>? measures,
    PartPlayback? playback,
    Object? transposition = _keep,
    Object? tabTuning = _keep,
    bool? linked,
    bool? squareBracket,
    int? staffLines,
    Object? drumMap = _keep,
  }) => Part(
    staffLines: staffLines ?? this.staffLines,
    drumMap: identical(drumMap, _keep)
        ? this.drumMap
        : drumMap as List<DrumPiece>?,
    squareBracket: squareBracket ?? this.squareBracket,
    linked: linked ?? this.linked,
    tabTuning: identical(tabTuning, _keep)
        ? this.tabTuning
        : tabTuning as List<int>?,
    transposition: identical(transposition, _keep)
        ? this.transposition
        : transposition as Transposition?,
    id: id ?? this.id,
    name: name ?? this.name,
    staff: staff ?? this.staff,
    measures: measures ?? this.measures,
    playback: playback ?? this.playback,
  );

  static const Object _keep = Object();

  int get measureCount => measures.length;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Part(id: $id, name: $name, measures: ${measures.length})');
    for (final measure in measures) {
      buffer.write(measure);
    }
    return buffer.toString();
  }
}
