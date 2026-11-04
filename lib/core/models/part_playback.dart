import 'transposition.dart';

/// Saved instrument sound and mixer state. MIDI programs are zero-based;
/// volume is a percentage and pan is -90 (left) through +90 (right).
class PartPlayback {
  const PartPlayback({
    this.program = 0,
    this.volume = 100,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
  });

  final int program;
  final double volume;
  final double pan;
  final bool mute;
  final bool solo;

  bool get isValid =>
      program >= 0 &&
      program < 128 &&
      volume.isFinite &&
      volume >= 0 &&
      volume <= 100 &&
      pan.isFinite &&
      pan >= -90 &&
      pan <= 90;
  int get midiVolume => (volume * 127 / 100).round();
  int get midiPan => pan == 0 ? 64 : ((pan + 90) * 127 / 180).round();

  PartPlayback copyWith({
    int? program,
    double? volume,
    double? pan,
    bool? mute,
    bool? solo,
  }) => PartPlayback(
    program: program ?? this.program,
    volume: volume ?? this.volume,
    pan: pan ?? this.pan,
    mute: mute ?? this.mute,
    solo: solo ?? this.solo,
  );

  Map<String, dynamic> toJson() => {
    'program': program,
    'volume': volume,
    'pan': pan,
    'mute': mute,
    'solo': solo,
  };
  factory PartPlayback.fromJson(Map<String, dynamic> json) {
    final value = PartPlayback(
      program: json['program'] as int? ?? 0,
      volume: (json['volume'] as num?)?.toDouble() ?? 100,
      pan: (json['pan'] as num?)?.toDouble() ?? 0,
      mute: json['mute'] == true,
      solo: json['solo'] == true,
    );
    return value.isValid ? value : const PartPlayback();
  }
  @override
  bool operator ==(Object other) =>
      other is PartPlayback &&
      program == other.program &&
      volume == other.volume &&
      pan == other.pan &&
      mute == other.mute &&
      solo == other.solo;
  @override
  int get hashCode => Object.hash(program, volume, pan, mute, solo);
}

/// GM bank 0. Names describe sounds only: choosing one never transposes notes.
const gmSounds = <String>[
  'Acoustic grand piano',
  'Bright piano',
  'Electric grand piano',
  'Honky-tonk piano',
  'Electric piano 1',
  'Electric piano 2',
  'Harpsichord',
  'Clavinet',
  'Celesta',
  'Glockenspiel',
  'Music box',
  'Vibraphone',
  'Marimba',
  'Xylophone',
  'Tubular bells',
  'Dulcimer',
  'Drawbar organ',
  'Percussive organ',
  'Rock organ',
  'Church organ',
  'Reed organ',
  'Accordion',
  'Harmonica',
  'Tango accordion',
  'Nylon guitar',
  'Steel guitar',
  'Jazz guitar',
  'Clean guitar',
  'Muted guitar',
  'Overdriven guitar',
  'Distortion guitar',
  'Guitar harmonics',
  'Acoustic bass',
  'Finger bass',
  'Pick bass',
  'Fretless bass',
  'Slap bass 1',
  'Slap bass 2',
  'Synth bass 1',
  'Synth bass 2',
  'Violin',
  'Viola',
  'Cello',
  'Contrabass',
  'Tremolo strings',
  'Pizzicato strings',
  'Orchestral harp',
  'Timpani',
  'String ensemble 1',
  'String ensemble 2',
  'Synth strings 1',
  'Synth strings 2',
  'Choir aahs',
  'Voice oohs',
  'Synth voice',
  'Orchestra hit',
  'Trumpet',
  'Trombone',
  'Tuba',
  'Muted trumpet',
  'French horn',
  'Brass section',
  'Synth brass 1',
  'Synth brass 2',
  'Soprano sax',
  'Alto sax',
  'Tenor sax',
  'Baritone sax',
  'Oboe',
  'English horn',
  'Bassoon',
  'Clarinet',
  'Piccolo',
  'Flute',
  'Recorder',
  'Pan flute',
  'Blown bottle',
  'Shakuhachi',
  'Whistle',
  'Ocarina',
  'Square lead',
  'Saw lead',
  'Calliope lead',
  'Chiff lead',
  'Charang lead',
  'Voice lead',
  'Fifths lead',
  'Bass and lead',
  'New age pad',
  'Warm pad',
  'Polysynth pad',
  'Choir pad',
  'Bowed pad',
  'Metallic pad',
  'Halo pad',
  'Sweep pad',
  'Rain',
  'Soundtrack',
  'Crystal',
  'Atmosphere',
  'Brightness',
  'Goblins',
  'Echoes',
  'Sci-fi',
  'Sitar',
  'Banjo',
  'Shamisen',
  'Koto',
  'Kalimba',
  'Bag pipe',
  'Fiddle',
  'Shanai',
  'Tinkle bell',
  'Agogo',
  'Steel drums',
  'Woodblock',
  'Taiko drum',
  'Melodic tom',
  'Synth drum',
  'Reverse cymbal',
  'Guitar fret noise',
  'Breath noise',
  'Seashore',
  'Bird tweet',
  'Telephone ring',
  'Helicopter',
  'Applause',
  'Gunshot',
];

/// The usual sound for an instrument named [name]; a numbered part such as
/// "Violin II" or "Flute 1" sounds as its instrument.
int defaultProgramFor(String name) => switch (instrumentKey(name)) {
  'piccolo' => 72,
  'flute' || 'flutes' => 73,
  'oboe' || 'oboes' => 68,
  'violin' => 40,
  'viola' => 41,
  'cello' || 'violoncello' => 42,
  // MuseScore Studio's string sections sound as a string ensemble.
  'violins' || 'violas' || 'violoncellos' || 'contrabasses' => 48,
  'double bass' => 43,
  'guitar' || 'classical guitar' || 'guitar tab' => 24,
  // MuseScore Studio's bass guitar is picked; its band guitars are clean
  // electric guitars.
  'bass guitar' => 34,
  'lead guitar' || 'rhythm guitar' || 'electric guitar' => 27,
  'acoustic bass' => 32,
  'trumpet' || 'trumpet in bb' || 'trumpets in bb' => 56,
  'bassoon' || 'bassoons' => 70,
  'clarinet in bb' ||
  'clarinets in bb' ||
  'clarinet in eb' ||
  'bass clarinet' => 71,
  'soprano saxophone' => 64,
  'alto saxophone' || 'alto sax' => 65,
  'tenor saxophone' || 'tenor sax' => 66,
  'baritone saxophone' || 'bari sax' => 67,
  'horn in f' || 'horns in f' || 'horn' => 60,
  'tuba' || 'euphonium' => 58,
  'trombone' => 57,
  'timpani' => 47,
  'glockenspiel' => 9,
  'organ' => 19,
  // MuseScore Studio declares its generic percussion staves this way.
  'percussion' => 48,
  // MuseScore Studio's voices sound as choir aahs.
  'voice' ||
  'bass voice' ||
  'soprano' ||
  'alto' ||
  'tenor' ||
  'bass' ||
  'lead vocals' ||
  'backing vocals' => 52,
  _ => 0,
};
