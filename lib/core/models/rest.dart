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
  String toString() =>
      'Rest(duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      ')';
}