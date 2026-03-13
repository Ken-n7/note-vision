import 'measure.dart';

class Part {
  final String id;
  final String name;
  final List<Measure> measures;

  const Part({
    required this.id,
    required this.name,
    required this.measures,
  });

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