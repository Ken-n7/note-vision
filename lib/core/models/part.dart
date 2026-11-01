import 'measure.dart';
import 'part_playback.dart';

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
  });

  /// Whether this part continues the instrument of the part before it.
  bool get joinsPrevious => staff > 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'measures': measures.map((m) => m.toJson()).toList(),
    if (staff > 1) 'staff': staff,
    if (playback != const PartPlayback()) 'playback': playback.toJson(),
  };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
    id: json['id'] as String,
    name: json['name'] as String,
    staff: json['staff'] as int? ?? 1,
    playback: PartPlayback.fromJson(
      json['playback'] as Map<String, dynamic>? ?? {},
    ),
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
  }) => Part(
    id: id ?? this.id,
    name: name ?? this.name,
    staff: staff ?? this.staff,
    measures: measures ?? this.measures,
    playback: playback ?? this.playback,
  );

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
