import 'score_symbol.dart';

class TimeSignature extends ScoreSymbol {
  final int beats; // numerator
  final int beatType; // denominator

  const TimeSignature({
    required this.beats,
    required this.beatType,
  });

  @override
  String toString() => 'TimeSignature($beats/$beatType)';
}