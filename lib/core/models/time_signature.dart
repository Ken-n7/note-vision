import 'score_symbol.dart';

class TimeSignature extends ScoreSymbol {
  final int beats; // numerator
  final int beatType; // denominator

  const TimeSignature({
    required this.beats,
    required this.beatType,
  });

  @override
  Map<String, dynamic> toJson() => {
        'symbolType': 'timeSignature',
        'beats': beats,
        'beatType': beatType,
      };

  factory TimeSignature.fromJson(Map<String, dynamic> json) => TimeSignature(
        beats: json['beats'] as int,
        beatType: json['beatType'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is TimeSignature &&
      other.beats == beats &&
      other.beatType == beatType;

  @override
  int get hashCode => Object.hash(beats, beatType);

  @override
  String toString() => 'TimeSignature($beats/$beatType)';
}