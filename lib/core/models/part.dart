import 'measure.dart';

class Part {
  final String id;
  final String name;
  final List<Measure> measures;

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
  });

  /// Whether this part continues the instrument of the part before it.
  bool get joinsPrevious => staff > 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'measures': measures.map((m) => m.toJson()).toList(),
        if (staff > 1) 'staff': staff,
      };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
        id: json['id'] as String,
        name: json['name'] as String,
        staff: json['staff'] as int? ?? 1,
        measures: (json['measures'] as List<dynamic>)
            .map((m) => Measure.fromJson(m as Map<String, dynamic>))
            .toList(),
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