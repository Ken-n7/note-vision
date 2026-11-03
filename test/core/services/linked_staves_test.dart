import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/linked_staves.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/tab_placement.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:xml/xml.dart';

/// What the editor does after an edit.
Score edited(Score next, Score prev) =>
    placeTabNotes(syncLinkedStaves(next, prev));

void main() {
  // MuseScore's export of Guitar + Tablature: each note written on both.
  final score = const MusicXmlScoreConverter().convert(
    XmlDocument.parse(
      File(
        'test/musescore_parity/reference/27_guitar_and_tab.musicxml',
      ).readAsStringSync(),
    ),
  );
  Note note(Score s, int part, int m, int i) =>
      s.parts[part].measures[m].symbols[i] as Note;

  test('a TAB staff repeating the staff above imports linked; plays once', () {
    expect(
      [for (final p in score.parts) (p.staff, p.isTab, p.linked)],
      [(1, false, false), (2, true, true)],
    );
    final notes = const PlaybackConverter()
        .buildEvents(score)
        .where((e) => !e.isRest);
    expect(notes, hasLength(8));
    expect(notes.map((e) => e.partIndex).toSet(), {0});
    expect(Score.fromJson(score.toJson()).parts[1].linked, isTrue);
  });

  test('an edit on the notation staff reaches the TAB staff', () {
    final g3 = note(score, 0, 0, 0);
    final next = edited(
      score.replaceSymbolAt(0, 0, 0, g3.copyWith(step: 'A')),
      score,
    );
    final tab = note(next, 1, 0, 0);
    expect((tab.step, tab.octave, tab.string, tab.fret), ('A', 3, 3, 2));
    // The TAB note stays itself: its ID, staff and voice.
    final before = note(score, 1, 0, 0);
    expect(
      (tab.reviewId, tab.staff, tab.voice),
      (before.reviewId, before.staff, before.voice),
    );
    final xml = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(next),
    );
    final first = xml
        .findAllElements('note')
        .where((n) => n.getElement('staff')?.innerText == '2')
        .first;
    expect(first.findAllElements('step').single.innerText, 'A');
    expect(first.findAllElements('fret').single.innerText, '2');
  });

  test('an edit on the TAB staff reaches the notation staff', () {
    final next = edited(score.deleteSymbolAt(1, 1, 3), score);
    expect(next.parts[0].measures[1].symbols, hasLength(4));
    // The F♯ went; the rest after it stays.
    expect(next.parts[0].measures[1].symbols.last, isA<Rest>());
    expect(next.parts[0].measures[1].clef, score.parts[0].measures[1].clef);
  });

  test('a TAB staff with music of its own stays independent', () {
    final other = score.replaceSymbolAt(
      1,
      0,
      0,
      note(score, 1, 0, 0).copyWith(step: 'C'),
    );
    expect(linkRepeatedTabStaves(other.parts).last.linked, isFalse);
  });

  test('Guitar + tablature starts as a linked pair', () {
    final s = buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates
            .firstWhere((t) => t.name == 'Guitar + tablature')
            .staves,
      ),
      id: 'x',
    );
    expect(
      [for (final p in s.parts) (p.name, p.isTab, p.linked)],
      [('Guitar', false, false), ('Guitar', true, true)],
    );
    final added = edited(
      s.insertSymbolAt(
        0,
        0,
        0,
        const Note(step: 'E', octave: 2, duration: 2, type: 'quarter'),
      ),
      s,
    );
    expect((note(added, 1, 0, 0).string, note(added, 1, 0, 0).fret), (6, 0));
  });
  test('the Staves sheet adds a linked TAB staff, and moving it unlinks', () {
    final guitar = buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates.firstWhere((t) => t.name == 'Guitar').staves,
      ),
      id: 'x',
    );
    final added = EditorState(score: guitar).rearrangeParts([
      (from: 0, name: 'Classical Guitar', clef: null, joinsPrevious: false),
      (
        from: null,
        name: 'Guitar',
        clef: const Clef(sign: 'G', line: 2, octave: -1),
        joinsPrevious: false,
      ),
      (from: null, name: 'Guitar', clef: Clef.tab, joinsPrevious: true),
    ]);
    expect([for (final p in added.score.parts) p.linked], [false, false, true]);
    final moved = added.rearrangeParts([
      (from: 2, name: 'Guitar', clef: null, joinsPrevious: true),
      (from: 0, name: 'Classical Guitar', clef: null, joinsPrevious: false),
      (from: 1, name: 'Guitar', clef: null, joinsPrevious: false),
    ]);
    expect(
      [for (final p in moved.score.parts) p.linked],
      [false, false, false],
    );
  });
}
