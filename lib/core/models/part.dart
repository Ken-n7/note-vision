import 'measure.dart';
import 'part_playback.dart';
import 'transposition.dart';

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
  });

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
  };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
    id: json['id'] as String,
    name: json['name'] as String,
    staff: json['staff'] as int? ?? 1,
    playback: PartPlayback.fromJson(
      json['playback'] as Map<String, dynamic>? ?? {},
    ),
    transposition: Transposition.fromJson(json['transposition']),
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
  }) => Part(
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
