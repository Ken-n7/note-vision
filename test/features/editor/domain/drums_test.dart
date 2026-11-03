import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/drum_kit.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:xml/xml.dart';

Score imported() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File('test/musescore_parity/cases/24_drums.musicxml').readAsStringSync(),
  ),
);

/// A drum kit and a piano, 4 bars of 4/4, the drum staff's first bar
/// selected.
EditorState band() => EditorState(
  score: buildNewScore(
    const NewScoreOptions(
      staves: [
        (name: 'Drum Kit', clef: Clef.percussion, grand: false),
        (name: 'Piano', clef: Clef(sign: 'G', line: 2), grand: false),
      ],
      bars: 4,
    ),
    id: 'band',
  ),
).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);

List<Note> drumNotes(Score score) => [
  for (final s in score.parts.first.measures.first.symbols)
    if (s is Note) s,
];

void main() {
  test('drum notes import with their kit pieces and play on channel 10', () {
    final score = imported();
    expect(score.parts.single.isPercussion, isTrue);
    final notes = drumNotes(score);
    expect(notes.first.drum, 42); // closed hi-hat
    expect(notes.first.notehead, 'x');
    expect({for (final n in notes) n.drum}, {36, 38, 42, 46});
    final events = const PlaybackConverter().buildEvents(score);
    expect(events.first.midiNote, 42);
    expect(PlaybackMix(score, {0}).channels, {0: 9});
  });

  test('letters enter kit pieces in their voices; a piece can be changed', () {
    var s = band().enterDrum(drumForShortcut('C')!, eighthDuration);
    s = s.enterDrum(drumForShortcut('A')!, quarterDuration);
    final notes = drumNotes(s.score);
    final hiHat = notes.firstWhere((n) => n.drum == 42);
    final kick = notes.firstWhere((n) => n.drum == 36);
    expect((hiHat.step, hiHat.octave, hiHat.notehead), ('G', 5, 'x'));
    expect((kick.step, kick.octave, kick.voice), ('F', 4, 2));

    final index = s.score.parts.first.measures.first.symbols.indexOf(hiHat);
    final snare = s
        .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: index)
        .setSelectedDrum(drumForShortcut('B')!);
    final changed = snare.selectedSymbol as Note;
    expect((changed.drum, changed.step, changed.notehead), (38, 'C', null));
  });

  test('a height on a drum staff finds the piece written there', () {
    expect(drumAt('G', 5).name, 'Closed Hi-Hat');
    expect(drumAt('F', 4).name, 'Bass Drum');
    expect(drumAt('D', 4).name, 'Pedal Hi-Hat');
    expect(drumAt('B', 4).name, 'Snare'); // nearest
  });

  test('transposing leaves drums where they are', () {
    final score = imported();
    final up = const Transposer().transpose(
      score,
      const TransposeOptions(mode: TransposeMode.byInterval, interval: 4),
    );
    expect(
      drumNotes(up).map((n) => n.pitch),
      drumNotes(score).map((n) => n.pitch),
    );
  });

  test('drums survive saving and a MusicXML round trip', () {
    final s = band()
        .enterDrum(drumForShortcut('D')!, quarterDuration)
        .enterDrum(drumForShortcut('B')!, quarterDuration);
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(s.score.toJson())) as Map<String, dynamic>,
    );
    final xml = const MusicXmlExportService().toMusicXml(saved);
    expect(xml, contains('<sign>percussion</sign>'));
    expect(xml, contains('<midi-unpitched>47</midi-unpitched>'));
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(reread.parts.first.isPercussion, isTrue);
    expect(drumNotes(reread).map((n) => (n.drum, n.notehead)), [
      (46, 'circle-x'),
      (38, null),
    ]);
  });
}
