import 'part.dart';

class Score {
  final String id;
  final String title;
  final String composer;
  final List<Part> parts;

  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.parts,
  });

  int get partCount => parts.length;

  int get totalMeasures =>
      parts.fold(0, (sum, part) => sum + part.measures.length);

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Score(');
    buffer.writeln('  id: $id');
    buffer.writeln('  title: $title');
    buffer.writeln('  composer: $composer');
    buffer.writeln('  parts: ${parts.length}');
    buffer.writeln('  totalMeasures: $totalMeasures');
    buffer.writeln(')');
    for (final part in parts) {
      buffer.write(part);
    }
    return buffer.toString();
  }
}