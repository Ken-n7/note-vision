import 'score_symbol.dart';

class Rest extends ScoreSymbol {
  final int duration; // effective divisions, including augmentation dots
  final String type; // whole, half, quarter, eighth, etc.
  final int? voice;
  final int? staff;
  final int dots;

  /// The detector's confidence for a scanned rest; null otherwise.
  final double? confidence;

  const Rest({
    required this.duration,
    required this.type,
    this.voice,
    this.staff,
    this.dots = 0,
    this.confidence,
  });

  @override
  Map<String, dynamic> toJson() => {
        'symbolType': 'rest',
        'duration': duration,
        'type': type,
        if (voice != null) 'voice': voice,
        if (staff != null) 'staff': staff,
        if (dots > 0) 'dots': dots,
        if (confidence != null) 'confidence': confidence,
      };

  factory Rest.fromJson(Map<String, dynamic> json) => Rest(
        duration: json['duration'] as int,
        type: json['type'] as String,
        voice: json['voice'] as int?,
        staff: json['staff'] as int?,
        dots: json['dots'] as int? ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  @override
  String toString() =>
      'Rest(duration: $duration, type: $type'
      '${voice != null ? ', voice: $voice' : ''}'
      '${staff != null ? ', staff: $staff' : ''}'
      '${dots > 0 ? ', dots: $dots' : ''}'
      ')';
}
