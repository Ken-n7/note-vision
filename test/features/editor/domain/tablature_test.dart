import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/tablature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/tab_placement.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:xml/xml.dart';

Score imported() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File(
      'test/musescore_parity/cases/25_tablature.musicxml',
    ).readAsStringSync(),
  ),
);

List<(int?, int?)> places(Score score, int measure) => [
  for (final s in score.parts.single.measures[measure].symbols)
    if (s is Note) (s.string, s.fret),
];

void main() {
  test('a pitch goes on the lowest fret, or stays on its string', () {
    expect(tabPosition(40, standardGuitarTuning), (string: 6, fret: 0));
    expect(tabPosition(67, standardGuitarTuning), (string: 1, fret: 3));
    // B3 is open on string 2, or fret 4 on string 3 when asked.
    expect(tabPosition(59, standardGuitarTuning), (string: 2, fret: 0));
    expect(tabPosition(59, standardGuitarTuning, string: 3), (
      string: 3,
      fret: 4,
    ));
    expect(tabPosition(30, standardGuitarTuning), isNull);
  });

  test('tablature imports its tuning, strings and frets, and plays', () {
    final score = imported();
    final part = score.parts.single;
    expect(part.isTab, isTrue);
    expect(part.tabTuning, standardGuitarTuning);
    expect(places(score, 0), [(6, 0), (5, 2), (4, 2), (3, 1)]);
    expect(
      const PlaybackConverter()
          .buildEvents(score)
          .take(4)
          .map((e) => e.midiNote),
      [40, 47, 52, 56],
    );
  });

  test('moving a tab note keeps its string and changes its fret', () {
    // E3, string 4 fret 2, moves up to F3: string 4 fret 3.
    final state = EditorState(score: imported())
        .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 2)
        .moveSelectedPitch(1);
    final placed = placeTabNotes(state.score);
    expect(places(placed, 0)[2], (4, 3));
    expect(identical(placeTabNotes(placed), placed), isTrue);
  });

  test('a new tablature score keeps its notes through saving and MusicXML', () {
    var state = EditorState(
      score: buildNewScore(
        NewScoreOptions(
          staves: scoreTemplates
              .firstWhere((t) => t.name == 'Guitar tablature')
              .staves,
          bars: 2,
        ),
        id: 'tab',
      ),
    ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
    state = state.enterNote('G', quarterDuration);
    final score = placeTabNotes(state.score);
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.parts.single.tabTuning, standardGuitarTuning);
    final xml = const MusicXmlExportService().toMusicXml(saved);
    expect(xml, contains('<staff-lines>6</staff-lines>'));
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(reread.parts.single.isTab, isTrue);
    expect(places(reread, 0), places(score, 0));
    expect(places(score, 0).single.$2, isNotNull);
  });
}
