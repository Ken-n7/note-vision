import 'score_symbol.dart';

class Note extends ScoreSymbol {
  final String step; // C, D, E, F, G, A, B
  final int octave; // usually 0-9
  final int? alter; // -1 = flat, 1 = sharp, etc.
  final int duration; // in divisions
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice; // optional
  final int? staff; // optional
  final bool beamed; // true when this eighth note belongs to a beamed group

  const Note({
    required this.step,
    required this.octave,
    this.alter,
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
    this.beamed = false,
  });

  @override
  Map<String, dynamic> toJson() => {
        'symbolType': 'note',
        'step': step,
        'octave': octave,
        if (alter != null) 'alter': alter,
        'duration': duration,
        'type': type,
        if (voice != null) 'voice': voice,
        if (staff != null) 'staff': staff,
        if (beamed) 'beamed': true,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        step: json['step'] as String,
        octave: json['octave'] as int,
        alter: json['alter'] as int?,
        duration: json['duration'] as int,
        type: json['type'] as String,
        voice: json['voice'] as int?,
        staff: json['staff'] as int?,
        beamed: json['beamed'] as bool? ?? false,
      );

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
      '${beamed ? ', beamed: true' : ''}'
      ')';
}