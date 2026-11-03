import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/widgets/score_notation/voice_layout.dart';

Note n(String type, int duration, {int? voice, bool chord = false}) => Note(
  step: 'C',
  octave: 5,
  type: type,
  duration: duration,
  voice: voice,
  isChordTone: chord,
);

void main() {
  test('one voice keeps one column per symbol, chord tones shared', () {
    final layout = VoiceLayout.of([
      const Clef(sign: 'G', line: 2),
      n('quarter', 2),
      n('quarter', 2, chord: true),
      n('half', 4),
    ]);
    expect(layout.columns, [0, 1, 1, 2]);
    expect(layout.columnCount, 3);
    expect(layout.multiVoice, isFalse);
    expect(layout.stemUp(1), isNull);
    expect(layout.restOffset(1), 0);
  });

  test('voices share columns where they start together', () {
    // Voice 1: half, half. Voice 2: quarter rest, quarter, half.
    final layout = VoiceLayout.of([
      n('half', 4, voice: 1),
      n('half', 4, voice: 1),
      const Rest(duration: 2, type: 'quarter', voice: 2),
      n('quarter', 2, voice: 2),
      n('half', 4, voice: 2),
    ]);
    expect(layout.columns, [0, 2, 0, 1, 2]);
    expect(layout.columnCount, 3);
    expect(
      [for (var i = 0; i < 5; i++) layout.stemUp(i)],
      [true, true, false, false, false],
    );
    expect(layout.restOffset(2), 2);
  });
}
