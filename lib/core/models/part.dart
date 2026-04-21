import 'measure.dart';

class Part {
  final String id;
  final String name;
  final List<Measure> measures;

  const Part({required this.id, required this.name, required this.measures});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'measures': measures.map((m) => m.toJson()).toList(),
  };

  factory Part.fromJson(Map<String, dynamic> json) => Part(
    id: json['id'] as String,
    name: json['name'] as String,
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
