import '../models/key_signature.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/part.dart';

/// Tracks key signature and accidentals through one part, as a reader does.
///
/// [Note.alter] is the accidental *written* before the note (null = none,
/// 0 = natural), which is what the editor draws. What the note *sounds* also
/// depends on the key signature and on accidentals earlier in the measure,
/// which hold to the barline for that pitch.
///
/// Call [startMeasure] at each measure, then [sounding] or [written] for its
/// notes in order.
class Accidentals {
  KeySignature? _key;
  final _carried = <String, int>{}; // 'F4' -> alter, until the barline

  static const _sharpOrder = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
  static const _flatOrder = ['B', 'E', 'A', 'D', 'G', 'C', 'F'];

  /// What [key] does to [step]: 1 sharp, -1 flat, 0 nothing.
  static int keyAlter(KeySignature? key, String step) {
    final fifths = key?.fifths ?? 0;
    final s = step.toUpperCase();
    if (fifths > 0 && _sharpOrder.take(fifths).contains(s)) return 1;
    if (fifths < 0 && _flatOrder.take(-fifths).contains(s)) return -1;
    return 0;
  }

  void startMeasure(Measure measure) {
    _key = measure.keySignature ?? _key;
    _carried.clear();
  }

  String _pitch(Note note) => '${note.step.toUpperCase()}${note.octave}';

  int _expected(Note note) =>
      _carried[_pitch(note)] ?? keyAlter(_key, note.step);

  /// The alteration [note] sounds with, given what it has written.
  int sounding(Note note) {
    final written = note.alter;
    if (written != null) _carried[_pitch(note)] = written;
    return written ?? _expected(note);
  }

  /// The accidental to write for a note that sounds with alteration
  /// [soundingAlter]: null when the key and the measure already give it.
  int? written(Note note, int soundingAlter) {
    if (soundingAlter == _expected(note)) return null;
    _carried[_pitch(note)] = soundingAlter;
    return soundingAlter;
  }

  /// [part] with each note's alter read as the sounding alteration (as in a
  /// MusicXML `<alter>`) and turned into the accidental to write.
  static Part writtenFromSounding(Part part) {
    final state = Accidentals();
    return Part(
      id: part.id,
      name: part.name,
      measures: [
        for (final m in part.measures)
          () {
            state.startMeasure(m);
            return Measure(
              number: m.number,
              clef: m.clef,
              timeSignature: m.timeSignature,
              keySignature: m.keySignature,
              startsNewPage: m.startsNewPage,
              startsNewSystem: m.startsNewSystem,
              leftBarlineType: m.leftBarlineType,
              rightBarlineType: m.rightBarlineType,
              symbols: [
                for (final s in m.symbols)
                  s is Note
                      ? Note(
                          step: s.step,
                          octave: s.octave,
                          alter: state.written(s, s.alter ?? 0),
                          duration: s.duration,
                          type: s.type,
                          voice: s.voice,
                          staff: s.staff,
                          beamed: s.beamed,
                          dots: s.dots,
                          isChordTone: s.isChordTone,
                        )
                      : s,
              ],
            );
          }(),
      ],
    );
  }
}
