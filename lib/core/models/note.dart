import 'score_symbol.dart';

class Note extends ScoreSymbol {
  final String step; // C, D, E, F, G, A, B
  final int octave; // usually 0-9
  final int? alter; // -1 = flat, 1 = sharp, etc.
  final int duration; // in divisions
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice; // optional
  final int? staff; // optional

  const Note({
    required this.step,
    required this.octave,
    this.alter,
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
  });

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
      ')';
}