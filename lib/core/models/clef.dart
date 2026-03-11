import 'score_symbol.dart';

class Clef extends ScoreSymbol {
  final String sign; // G, F, C
  final int line; // staff line the clef sits on

  const Clef({
    required this.sign,
    required this.line,
  });

  @override
  String toString() => 'Clef(sign: $sign, line: $line)';
}