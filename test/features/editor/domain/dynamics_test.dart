import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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

/// Two bars of quarters (C D E F | G A B C), C selected.
EditorState music() => EditorState(
  score: NotationReviewService.ensureIdentity(
    Score(
      id: 's',
      title: 'Dynamics',
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
            Measure(number: 2, symbols: [q('G'), q('A'), q('B'), q('C')]),
          ],
        ),
      ],
    ),
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);

EditorState at(EditorState s, int measure, int symbol) =>
    s.selectSymbolAt(partIndex: 0, measureIndex: measure, symbolIndex: symbol);

List<int> velocities(EditorState s) => [
  for (final e in const PlaybackConverter().buildEvents(s.score)) e.velocity,
];

void main() {
  test('a dynamic goes on the first selected note and toggles off', () {
    final p = music().setDynamic('p');
    expect(p.selectedDynamic, 'p');
    expect(p.undoStack, hasLength(1));
    expect(p.setDynamic('p').selectedDynamic, isNull);
    expect(p.setDynamic('f').selectedDynamic, 'f');
  });

  test('a crescendo glides to the next louder dynamic, as MuseScore plays', () {
    // p on C, crescendo over D E F, f on G.
    var s = music().setDynamic('p');
    s = at(s, 0, 1).extendSelection(1).extendSelection(1);
    s = EditorCommand.crescendo.execute(s);
    s = at(s, 1, 0).setDynamic('f');
    expect(velocities(s), [49, 49, 64, 80, 96, 96, 96, 96]);
    // The same hairpin again removes it.
    final again = at(s, 0, 1).extendSelection(1).extendSelection(1);
    expect(EditorCommand.crescendo.execute(again).score.spanners, isEmpty);
  });

  test('sfz stresses one note; a hairpin with no target goes one level', () {
    var s = at(music().setDynamic('mf'), 0, 1).setDynamic('sfz');
    expect(velocities(s).take(3), [80, 112, 80]);
    // A diminuendo over the second bar from mf, with nothing after it,
    // falls to mp.
    s = at(s, 1, 0).extendSelectionByBar(1);
    s = EditorCommand.diminuendo.execute(s);
    expect(velocities(s).skip(4), [80, 76, 72, 68]);
  });

  test('dynamics and hairpins survive saving and a MusicXML round trip', () {
    var s = music().setDynamic('mp');
    s = EditorCommand.crescendo.execute(at(s, 0, 0).extendSelectionByBar(1));
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(s.score.toJson())) as Map<String, dynamic>,
    );
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(const MusicXmlExportService().toMusicXml(saved)),
    );
    expect(
      (reread.parts.single.measures.first.symbols.first as Note).dynamicMark,
      'mp',
    );
    final hairpin = reread.spanners.single;
    expect(hairpin.kind, SpannerKind.crescendo);
    final notes = [
      for (final n in reread.parts.single.measures.first.symbols)
        (n as Note).reviewId,
    ];
    expect((hairpin.from, hairpin.to), (notes.first, notes.last));
  });
}
