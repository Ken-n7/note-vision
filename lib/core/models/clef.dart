import 'score_symbol.dart';

class Clef extends ScoreSymbol {
  final String sign; // G, F, C
  final int line; // staff line the clef sits on

  /// Octaves the music sounds from where it is written: -1 for the tenor
  /// voice's and guitar's treble clef with an 8 below (MusicXML's
  /// `clef-octave-change`). A note's pitch is what sounds, as in MusicXML,
  /// so only its staff position follows this.
  final int octave;

  const Clef({required this.sign, required this.line, this.octave = 0});

  static const percussion = Clef(sign: 'percussion', line: 3);

  bool get isPercussion => sign == 'percussion';

  /// A tablature staff: lines are strings, notes are fret numbers.
  static const tab = Clef(sign: 'TAB', line: 5);

  bool get isTab => sign == 'TAB';

  /// The sign staff drawing passes around, carrying the octave (`G-1`), so
  /// [StaffPitchMapper] places notes for octave clefs. A percussion clef is
  /// `P`: its notes sit where a treble clef's would.
  String get layoutSign => isPercussion
      ? 'P'
      : isTab
      ? 'T'
      : octave == 0
      ? sign
      : '$sign$octave';

  @override
  Map<String, dynamic> toJson() => {
    'symbolType': 'clef',
    'sign': sign,
    'line': line,
    if (octave != 0) 'octave': octave,
  };

  factory Clef.fromJson(Map<String, dynamic> json) => Clef(
    sign: json['sign'] as String,
    line: json['line'] as int,
    octave: json['octave'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is Clef &&
      other.sign == sign &&
      other.line == line &&
      other.octave == octave;

  @override
  int get hashCode => Object.hash(sign, line, octave);

  @override
  String toString() =>
      'Clef(sign: $sign, line: $line${octave == 0 ? '' : ', octave: $octave'})';
}
