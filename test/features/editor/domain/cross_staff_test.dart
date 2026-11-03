import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:xml/xml.dart';

Score imported() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File(
      'test/musescore_parity/cases/26_cross_staff.musicxml',
    ).readAsStringSync(),
  ),
);

List<int> moves(Score score, int part) => [
  for (final s in score.parts[part].measures.first.symbols)
    if (s is Note) s.staffMove,
];

/// A piano with C D E F in the right hand, C selected.
EditorState piano() {
  var state = EditorState(
    score: buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates.firstWhere((t) => t.name == 'Piano').staves,
        bars: 1,
      ),
      id: 'p',
    ),
  ).copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
  for (final step in ['C', 'D', 'E', 'F']) {
    state = state.enterNote(step, quarterDuration);
  }
  return state.selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
}

void main() {
  test('a right-hand note on the lower staff stays in the right hand', () {
    final score = imported();
    expect(moves(score, 0), [1, 1, 1, 0, 0, 0, 0, 0]);
    expect(moves(score, 1), [0]); // the left hand's whole note
    // It keeps its time in the right hand's rhythm.
    final onsets = [
      for (final e in const ScoreTimelineBuilder().measure(score, 0, 0).symbols)
        e.onset,
    ];
    expect(onsets, [for (var i = 0; i < 8; i++) MusicalTime(i, 2)]);
  });

  test('a note moves to the staff below and back, one undo step each', () {
    final state = piano();
    expect(EditorCommand.staffAbove.unavailableReason(state), isNotNull);
    final down = EditorCommand.staffBelow.execute(state);
    expect((down.selectedSymbol as Note).staffMove, 1);
    expect(down.undoStack.length, state.undoStack.length + 1);
    expect(EditorCommand.staffBelow.unavailableReason(down), isNotNull);
    final back = EditorCommand.staffAbove.execute(down);
    expect((back.selectedSymbol as Note).staffMove, 0);
  });

  test('a cross-staff note survives saving and MusicXML', () {
    final score = EditorCommand.staffBelow.execute(piano()).score;
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
    );
    final xml = const MusicXmlExportService().toMusicXml(saved);
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(moves(reread, 0), [1, 0, 0, 0]);
  });

  test('a note without a second staff cannot move', () {
    final state =
        EditorState(
              score: buildNewScore(
                NewScoreOptions(staves: scoreTemplates.first.staves, bars: 1),
                id: 't',
              ),
            )
            .copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0)
            .enterNote('C', quarterDuration);
    expect(
      state.crossStaffUnavailableReason(1),
      'Move notes between the staves of one instrument',
    );
  });
}
