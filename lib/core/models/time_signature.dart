import 'score_symbol.dart';

class TimeSignature extends ScoreSymbol {
  final int beats; // numerator
  final int beatType; // denominator

  /// Drawn as a sign instead of digits: common time (C, 4/4) or cut time
  /// (¢, 2/2).
  final TimeSymbol? symbol;

  const TimeSignature({
    required this.beats,
    required this.beatType,
    this.symbol,
  });

  static const common = TimeSignature(
    beats: 4,
    beatType: 4,
    symbol: TimeSymbol.common,
  );
  static const cut = TimeSignature(
    beats: 2,
    beatType: 2,
    symbol: TimeSymbol.cut,
  );

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'timeSignature',
    'beats': beats,
    'beatType': beatType,
    if (symbol != null) 'symbol': symbol!.name,
  };

  factory TimeSignature.fromJson(Map<String, dynamic> json) => TimeSignature(
    beats: json['beats'] as int,
    beatType: json['beatType'] as int,
    symbol: TimeSymbol.values
        .where((s) => s.name == json['symbol'])
        .firstOrNull,
  );

  @override
  bool operator ==(Object other) =>
      other is TimeSignature &&
      other.beats == beats &&
      other.beatType == beatType &&
      other.symbol == symbol;

  @override
  int get hashCode => Object.hash(beats, beatType, symbol);

  @override
  String toString() =>
      'TimeSignature($beats/$beatType${symbol == null ? '' : ' ${symbol!.name}'})';
}

/// MusicXML's `<time symbol>` values that Note Vision draws.
enum TimeSymbol { common, cut }
