import 'clef.dart';
import 'key_signature.dart';
import 'note.dart';
import 'rest.dart';
import 'score_symbol.dart';
import 'time_signature.dart';

class Measure {
  final int number;
  final Clef? clef;
  final TimeSignature? timeSignature;
  final KeySignature? keySignature;
  final List<ScoreSymbol> symbols;

  const Measure({
    required this.number,
    this.clef,
    this.timeSignature,
    this.keySignature,
    required this.symbols,
  });

  List<Note> get notes => symbols.whereType<Note>().toList();

  List<Rest> get rests => symbols.whereType<Rest>().toList();

  int get symbolCount => symbols.length;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('  Measure $number:');
    if (clef != null) buffer.writeln('    $clef');
    if (timeSignature != null) buffer.writeln('    $timeSignature');
    if (keySignature != null) buffer.writeln('    $keySignature');
    for (final symbol in symbols) {
      buffer.writeln('    $symbol');
    }
    return buffer.toString();
  }
}