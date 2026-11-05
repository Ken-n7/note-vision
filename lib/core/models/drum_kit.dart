import 'note.dart';

/// Presets available in the bundled SoundFont's percussion bank (128).
const drumKitSounds = <int, String>{
  0: 'Standard kit',
  8: 'Room kit',
  16: 'Power kit',
  24: 'Electronic kit',
  25: 'TR-808 kit',
  32: 'Jazz kit',
  40: 'Brush kit',
  48: 'Orchestral kit',
};

/// One piece of a drum kit: its General MIDI key, where it is written on a
/// percussion staff, its notehead, voice (1 hands, stem up; 2 feet, stem
/// down) and the letter that enters it, as MuseScore Studio's drum kit has
/// them.
class DrumPiece {
  const DrumPiece(
    this.key,
    this.name,
    this.step,
    this.octave, {
    this.notehead,
    this.voice = 1,
    this.shortcut,
  });

  final int key;
  final String name, step;
  final int octave, voice;
  final String? notehead, shortcut;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'step': step,
    'octave': octave,
    if (notehead != null) 'notehead': notehead,
    'voice': voice,
    if (shortcut != null) 'shortcut': shortcut,
  };

  factory DrumPiece.fromJson(Map<String, dynamic> json) => DrumPiece(
    json['key'] as int,
    json['name'] as String,
    json['step'] as String,
    json['octave'] as int,
    notehead: json['notehead'] as String?,
    voice: json['voice'] as int? ?? 1,
    shortcut: json['shortcut'] as String?,
  );
}

/// MuseScore's orchestral percussion maps: every piece sits on the one
/// staff line (the middle of a treble staff), with stems up in voice 1.
const orchestralSnare = [
  DrumPiece(38, 'Snare', 'B', 4, shortcut: 'B'),
  DrumPiece(37, 'Side Stick', 'B', 4, notehead: 'x', shortcut: 'A'),
];
const orchestralBassDrum = [
  DrumPiece(36, 'Concert Bass Drum', 'B', 4, shortcut: 'A'),
];
const orchestralCymbals = [
  DrumPiece(57, 'Hand Cymbals', 'B', 4, shortcut: 'A'),
];

List<DrumPiece>? orchestralDrumsFor(String name) =>
    switch (name.toLowerCase()) {
      'snare drum' => orchestralSnare,
      'bass drum' => orchestralBassDrum,
      'cymbals' => orchestralCymbals,
      _ => null,
    };

const drumKit = <DrumPiece>[
  DrumPiece(36, 'Bass Drum', 'F', 4, voice: 2, shortcut: 'A'),
  DrumPiece(38, 'Snare', 'C', 5, shortcut: 'B'),
  DrumPiece(42, 'Closed Hi-Hat', 'G', 5, notehead: 'x', shortcut: 'C'),
  DrumPiece(46, 'Open Hi-Hat', 'G', 5, notehead: 'circle-x', shortcut: 'D'),
  DrumPiece(49, 'Crash Cymbal', 'A', 5, notehead: 'x', shortcut: 'E'),
  DrumPiece(51, 'Ride Cymbal', 'F', 5, notehead: 'x', shortcut: 'F'),
  DrumPiece(50, 'High Tom', 'E', 5, shortcut: 'G'),
  DrumPiece(41, 'Floor Tom', 'A', 4, shortcut: 'H'),
  DrumPiece(47, 'Low Tom', 'D', 5),
  DrumPiece(44, 'Pedal Hi-Hat', 'D', 4, notehead: 'x', voice: 2),
  DrumPiece(35, 'Bass Drum 2', 'E', 4, voice: 2),
  DrumPiece(37, 'Cross-stick', 'C', 5, notehead: 'slashed'),
  DrumPiece(53, 'Ride Bell', 'F', 5, notehead: 'diamond'),
  DrumPiece(55, 'Splash Cymbal', 'C', 6, notehead: 'x'),
  DrumPiece(57, 'Crash Cymbal 2', 'B', 5, notehead: 'x'),
  DrumPiece(52, 'China Cymbal', 'B', 5),
];

DrumPiece? drumPiece(int key) => drumKit.where((d) => d.key == key).firstOrNull;

/// The kit piece entered with [letter] (A bass drum … H floor tom).
DrumPiece? drumForShortcut(
  String letter, {
  Iterable<DrumPiece> pieces = drumKit,
}) => pieces.where((d) => d.shortcut == letter).firstOrNull;

/// The piece written at [step][octave], preferring the main kit pieces
/// (those with a letter); the nearest one when none sits there.
DrumPiece drumAt(String step, int octave, {List<DrumPiece> pieces = drumKit}) {
  if (pieces.isEmpty) pieces = drumKit;
  if (pieces.every(
    (p) => p.step == pieces.first.step && p.octave == pieces.first.octave,
  )) {
    return pieces.first;
  }
  int place(String s, int o) => o * 7 + 'CDEFGAB'.indexOf(s);
  final target = place(step, octave);
  final ranked = [...pieces]
    ..sort((a, b) {
      final distance = (place(a.step, a.octave) - target).abs().compareTo(
        (place(b.step, b.octave) - target).abs(),
      );
      if (distance != 0) return distance;
      return (a.shortcut == null ? 1 : 0) - (b.shortcut == null ? 1 : 0);
    });
  return ranked.first;
}

/// A note playing [piece], written as [type] lasting [divisions].
Note drumNote(
  DrumPiece piece,
  String type,
  int divisions, {
  int? voice,
  int? staff,
}) => Note(
  step: piece.step,
  octave: piece.octave,
  duration: divisions,
  type: type,
  voice: voice,
  staff: staff,
  drum: piece.key,
  notehead: piece.notehead,
);
