import 'score_symbol.dart';

class KeySignature extends ScoreSymbol {
  final int fifths; // negative = flats, positive = sharps, 0 = C major

  const KeySignature({required this.fifths});

  @override
  Map<String, dynamic> toJson() => {
        'symbolType': 'keySignature',
        'fifths': fifths,
      };

  factory KeySignature.fromJson(Map<String, dynamic> json) =>
      KeySignature(fifths: json['fifths'] as int);

  String get name {
    const keyNames = <int, String>{
      -7: 'Cb major',
      -6: 'Gb major',
      -5: 'Db major',
      -4: 'Ab major',
      -3: 'Eb major',
      -2: 'Bb major',
      -1: 'F major',
      0: 'C major',
      1: 'G major',
      2: 'D major',
      3: 'A major',
      4: 'E major',
      5: 'B major',
      6: 'F# major',
      7: 'C# major',
    };

    return keyNames[fifths] ?? 'Unknown key';
  }

  @override
  String toString() => 'KeySignature(fifths: $fifths, key: $name)';
}
