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

  Map<String, dynamic> toJson() => {
        'number': number,
        if (clef != null) 'clef': clef!.toJson(),
        if (timeSignature != null) 'timeSignature': timeSignature!.toJson(),
        if (keySignature != null) 'keySignature': keySignature!.toJson(),
        'symbols': symbols.map((s) => s.toJson()).toList(),
      };

  factory Measure.fromJson(Map<String, dynamic> json) => Measure(
        number: json['number'] as int,
        clef: json['clef'] != null
            ? Clef.fromJson(json['clef'] as Map<String, dynamic>)
            : null,
        timeSignature: json['timeSignature'] != null
            ? TimeSignature.fromJson(
                json['timeSignature'] as Map<String, dynamic>)
            : null,
        keySignature: json['keySignature'] != null
            ? KeySignature.fromJson(
                json['keySignature'] as Map<String, dynamic>)
            : null,
        symbols: (json['symbols'] as List<dynamic>)
            .map((s) => _symbolFromJson(s as Map<String, dynamic>))
            .toList(),
      );

  static ScoreSymbol _symbolFromJson(Map<String, dynamic> json) {
    return switch (json['symbolType'] as String) {
      'note' => Note.fromJson(json),
      'rest' => Rest.fromJson(json),
      'clef' => Clef.fromJson(json),
      'keySignature' => KeySignature.fromJson(json),
      'timeSignature' => TimeSignature.fromJson(json),
      final t => throw FormatException('Unknown symbolType: $t'),
    };
  }

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