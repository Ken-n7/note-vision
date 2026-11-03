import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note q(String step) =>
    Note(step: step, octave: 4, duration: 2, type: 'quarter');

/// One full 4/4 bar of quarters (C D E F), D selected.
EditorState music() => EditorState(
  score: NotationReviewService.ensureIdentity(
    Score(
      id: 's',
      title: 'Grace',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Piano',
          measures: [
            Measure(
              number: 1,
              timeSignature: const TimeSignature(beats: 4, beatType: 4),
              symbols: [q('C'), q('D'), q('E'), q('F')],
            ),
          ],
        ),
      ],
    ),
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 1);

/// (midi, onset ms, length ms) of each sounding event, at 120 BPM.
List<(int, int, int)> sounds(EditorState s) => [
  for (final e in const PlaybackConverter().buildEvents(s.score))
    (e.midiNote, e.baseOnsetMs, e.baseDurationMs),
];

void main() {
  test('a grace note goes before the selected note in a full bar', () {
    final s = EditorCommand.appoggiatura.execute(music());
    final symbols = s.score.parts.single.measures.single.symbols;
    expect(symbols, hasLength(5));
    expect((symbols[1] as Note).grace, Grace.appoggiatura);
    expect((symbols[1] as Note).step, 'D');
    expect(s.selectedSymbolIndex, 1);
    expect(s.undoStack, hasLength(1));
    // On a grace note the other kind changes it.
    final slashed = EditorCommand.acciaccatura.execute(s);
    expect((slashed.selectedSymbol as Note).grace, Grace.acciaccatura);
    expect(slashed.score.parts.single.measures.single.symbols, hasLength(5));
  });

  test('grace notes borrow their sound as MuseScore plays them', () {
    // An eighth appoggiatura takes half the quarter D from its start.
    final app = EditorCommand.appoggiatura.execute(music());
    expect(sounds(app), [
      (60, 0, 500),
      (62, 500, 250),
      (62, 750, 250),
      (64, 1000, 500),
      (65, 1500, 500),
    ]);
    // An acciaccatura takes it from the end of the C before.
    final acc = EditorCommand.acciaccatura.execute(music());
    expect(sounds(acc), [
      (60, 0, 250),
      (62, 250, 250),
      (62, 500, 500),
      (64, 1000, 500),
      (65, 1500, 500),
    ]);
  });

  test('a grace note does not break a beam between eighths', () {
    final e = Note(step: 'C', octave: 5, duration: 1, type: 'eighth');
    final symbols = [
      e.copyWith(beams: {1: BeamValue.begin}),
      e.copyWith(type: 'sixteenth', grace: Grace.acciaccatura),
      e.copyWith(beams: {1: BeamValue.end}),
    ];
    expect(BeamGrouping.groups(symbols), [
      [0, 2],
    ]);
  });

  test('grace notes survive saving and a MusicXML round trip', () {
    final s = EditorCommand.acciaccatura.execute(music());
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(s.score.toJson())) as Map<String, dynamic>,
    );
    final xml = const MusicXmlExportService().toMusicXml(saved);
    expect(xml, contains('<grace slash="yes"/>'));
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    final notes = reread.parts.single.measures.single.symbols.cast<Note>();
    expect(
      [for (final n in notes) n.grace],
      [null, Grace.acciaccatura, null, null, null],
    );
  });
}
