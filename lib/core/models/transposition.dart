/// How a transposing instrument's written notes sound, as MusicXML's
/// `<transpose>` says it: what is added to the written pitch. A B♭ clarinet
/// sounds a major second lower: diatonic −1, chromatic −2.
class Transposition {
  const Transposition({
    required this.diatonic,
    required this.chromatic,
    this.octave = 0,
  });

  final int diatonic, chromatic, octave;

  /// Semitones from written to sounding pitch.
  int get semitones => chromatic + 12 * octave;

  /// Staff steps from written to sounding pitch.
  int get steps => diatonic + 7 * octave;

  Transposition get inverse => Transposition(
    diatonic: -diatonic,
    chromatic: -chromatic,
    octave: -octave,
  );

  Map<String, dynamic> toJson() => {
    'diatonic': diatonic,
    'chromatic': chromatic,
    if (octave != 0) 'octave': octave,
  };

  static Transposition? fromJson(Object? json) => json is Map
      ? Transposition(
          diatonic: json['diatonic'] as int,
          chromatic: json['chromatic'] as int,
          octave: json['octave'] as int? ?? 0,
        )
      : null;

  @override
  bool operator ==(Object other) =>
      other is Transposition &&
      other.diatonic == diatonic &&
      other.chromatic == chromatic &&
      other.octave == octave;

  @override
  int get hashCode => Object.hash(diatonic, chromatic, octave);

  @override
  String toString() => 'Transposition($diatonic, $chromatic, $octave)';
}

/// The transposition MuseScore Studio gives an instrument named [name]
/// (numbered parts such as "Trumpet in Bb 2" included); null for concert
/// pitch instruments.
Transposition? transpositionFor(String name) {
  const bFlat = Transposition(diatonic: -1, chromatic: -2);
  const eFlatLow = Transposition(diatonic: -5, chromatic: -9);
  const octaveDown = Transposition(diatonic: 0, chromatic: 0, octave: -1);
  return switch (name.toLowerCase().replaceFirst(
    RegExp(r'\s+(i{1,3}|iv|v|\d+)$'),
    '',
  )) {
    'clarinet in bb' || 'trumpet in bb' || 'trumpet' => bFlat,
    'soprano saxophone' => bFlat,
    'alto saxophone' || 'alto sax' => eFlatLow,
    'tenor saxophone' || 'tenor sax' || 'bass clarinet' => const Transposition(
      diatonic: -1,
      chromatic: -2,
      octave: -1,
    ),
    'baritone saxophone' => const Transposition(
      diatonic: -5,
      chromatic: -9,
      octave: -1,
    ),
    'horn in f' || 'horn' => const Transposition(diatonic: -4, chromatic: -7),
    'double bass' ||
    'contrabass' ||
    'acoustic bass' ||
    'bass guitar' => octaveDown,
    'piccolo' => const Transposition(diatonic: 0, chromatic: 0, octave: 1),
    'glockenspiel' => const Transposition(diatonic: 0, chromatic: 0, octave: 2),
    _ => null,
  };
}
