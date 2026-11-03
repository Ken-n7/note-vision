/// A guitar's open strings as MIDI notes, lowest first (MusicXML's staff
/// line 1 is the lowest string): E2 A2 D3 G3 B3 E4.
const standardGuitarTuning = [40, 45, 50, 55, 59, 64];

/// Where [midi] is played on strings tuned to [tuning]: string 1 is the
/// highest, as MusicXML numbers them. Keeps [string] when it can play the
/// note; otherwise takes the lowest fret, preferring higher strings. Null
/// when no string reaches it.
({int string, int fret})? tabPosition(
  int midi,
  List<int> tuning, {
  int? string,
  int maxFret = 24,
}) {
  int open(int s) => tuning[tuning.length - s];
  if (string != null && string >= 1 && string <= tuning.length) {
    final fret = midi - open(string);
    if (fret >= 0 && fret <= maxFret) return (string: string, fret: fret);
  }
  ({int string, int fret})? best;
  for (var s = 1; s <= tuning.length; s++) {
    final fret = midi - open(s);
    if (fret < 0 || fret > maxFret) continue;
    if (best == null || fret < best.fret) best = (string: s, fret: fret);
  }
  return best;
}

/// The MIDI note of [step][octave] sounding with [alter] semitones.
int midiOf(String step, int alter, int octave) =>
    (octave + 1) * 12 + const [0, 2, 4, 5, 7, 9, 11]['CDEFGAB'.indexOf(step)] +
    alter;

/// A tab note's string and fret: its own when they still play its pitch,
/// else the best place for it.
({int string, int fret})? tabPlace(
  String step,
  int soundingAlter,
  int octave,
  List<int> tuning, {
  int? string,
}) => tabPosition(midiOf(step, soundingAlter, octave), tuning, string: string);

/// [midi] spelled with sharps: 61 is C♯4.
({String step, int alter, int octave}) spellMidi(int midi) {
  const names = [
    ('C', 0), ('C', 1), ('D', 0), ('D', 1), ('E', 0), ('F', 0),
    ('F', 1), ('G', 0), ('G', 1), ('A', 0), ('A', 1), ('B', 0),
  ];
  final (step, alter) = names[midi % 12];
  return (step: step, alter: alter, octave: midi ~/ 12 - 1);
}
