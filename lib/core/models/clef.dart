import 'score_symbol.dart';

class Clef extends ScoreSymbol {
  final String sign; // G, F, C
  final int line; // staff line the clef sits on

  const Clef({
    required this.sign,
    required this.line,
  });

  @override
  Map<String, dynamic> toJson() => {
        'symbolType': 'clef',
        'sign': sign,
        'line': line,
      };

  factory Clef.fromJson(Map<String, dynamic> json) => Clef(
        sign: json['sign'] as String,
        line: json['line'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is Clef && other.sign == sign && other.line == line;

  @override
  int get hashCode => Object.hash(sign, line);

  @override
  String toString() => 'Clef(sign: $sign, line: $line)';
}