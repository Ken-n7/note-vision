import 'score_symbol.dart';

class Rest extends ScoreSymbol {
  final int duration; // in divisions
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice;
  final int? staff;

  const Rest({
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
  });

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'rest',
    'duration': duration,
    'type': type,
    if (voice != null) 'voice': voice,
    if (staff != null) 'staff': staff,
  };

  factory Rest.fromJson(Map<String, dynamic> json) => Rest(
    duration: json['duration'] as int,
    type: json['type'] as String,
    voice: json['voice'] as int?,
    staff: json['staff'] as int?,
  );

  @override
  String toString() =>
      'Rest(duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      ')';
}
