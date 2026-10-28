import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/navigation_mark.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

const steps = ['C', 'D', 'E', 'F', 'G', 'A'];

Part part(String id, int bars) => Part(
  id: id,
  name: id,
  measures: [
    for (var i = 0; i < bars; i++)
      Measure(
        number: i + 1,
        timeSignature: i == 0
            ? const TimeSignature(beats: 4, beatType: 4)
            : null,
        symbols: [Note(step: steps[i], octave: 4, duration: 8, type: 'whole')],
      ),
  ],
);

/// One whole note a bar (C D E F …), the first bar selected.
EditorState music({int bars = 4, int parts = 1}) => EditorState(
  score: NotationReviewService.ensureIdentity(
    Score(
      id: 's',
      title: 'Repeats',
      composer: '',
      parts: [for (var p = 0; p < parts; p++) part('P${p + 1}', bars)],
    ),
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);

EditorState bar(EditorState s, int index, [int through = 0]) {
  var next = s.selectSymbolAt(
    partIndex: 0,
    measureIndex: index,
    symbolIndex: 0,
  );
  for (var i = 0; i < through; i++) {
    next = next.extendSelectionByBar(1);
  }
  return next;
}

List<int> order(EditorState s) =>
    ScoreTimelineBuilder.playOrder(s.score.parts.first.measures);

List<int> played(EditorState s) => [
  for (final e in const PlaybackConverter().buildEvents(s.score)) e.midiNote,
];

void main() {
  test('repeat signs go on the edges of the selected bars, and toggle', () {
    var s = bar(music(), 1, 1).toggleBarSign(BarSign.startRepeat);
    s = s.toggleBarSign(BarSign.endRepeat);
    final bars = s.score.parts.first.measures;
    expect(bars[1].leftBarlineType, BarlineType.repeatStart);
    expect(bars[2].rightBarlineType, BarlineType.repeatEnd);
    expect(s.barSignOn(BarSign.startRepeat), isTrue);
    expect(s.undoStack, hasLength(2));
    expect(order(s), [0, 1, 2, 1, 2, 3]);
    expect(played(s), [60, 62, 64, 62, 64, 65]);

    final off = s.toggleBarSign(BarSign.endRepeat);
    expect(off.score.parts.first.measures[2].rightBarlineType, isNull);
    expect(order(off), [0, 1, 2, 3]);
  });

  test('first and second endings play once each', () {
    var s = bar(music(), 1).toggleBarSign(BarSign.endRepeat);
    s = s.toggleBarSign(BarSign.firstEnding);
    s = bar(s, 2, 1).toggleBarSign(BarSign.secondEnding);
    final bars = s.score.parts.first.measures;
    expect(bars[1].endingStart, [1]);
    expect(bars[1].endingEnd, EndingEnd.closed);
    expect(bars[2].endingStart, [2]);
    expect(bars[3].endingEnd, EndingEnd.open);
    expect(order(s), [0, 1, 0, 2, 3]);
  });

  test('D.C. al Fine and D.S. al Coda follow MuseScore\'s play order', () {
    var fine = bar(music(), 1).toggleBarSign(BarSign.fine);
    fine = bar(fine, 3).toggleBarSign(BarSign.daCapoAlFine);
    expect(order(fine), [0, 1, 2, 3, 0, 1]);

    var coda = bar(music(bars: 5), 1).toggleBarSign(BarSign.segno);
    coda = bar(coda, 2).toggleBarSign(BarSign.toCoda);
    coda = bar(coda, 3).toggleBarSign(BarSign.dalSegnoAlCoda);
    coda = bar(coda, 4).toggleBarSign(BarSign.coda);
    expect(order(coda), [0, 1, 2, 3, 1, 2, 4]);
    // One jump per bar: D.C. replaces D.S. al Coda.
    final replaced = bar(coda, 3).toggleBarSign(BarSign.daCapo);
    expect(replaced.score.parts.first.measures[3].navigation, [
      NavigationMark.daCapo,
    ]);
  });

  test('signs apply to every staff and survive saving and MusicXML', () {
    var s = bar(music(parts: 2), 0, 1).toggleBarSign(BarSign.endRepeat);
    s = bar(s, 1).toggleBarSign(BarSign.firstEnding);
    s = bar(s, 2).toggleBarSign(BarSign.secondEnding);
    s = bar(s, 3).toggleBarSign(BarSign.finalBar);
    for (final p in s.score.parts) {
      expect(p.measures[1].rightBarlineType, BarlineType.repeatEnd);
      expect(p.measures[2].endingStart, [2]);
    }

    final saved = Score.fromJson(
      jsonDecode(jsonEncode(s.score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.notationProjection(), s.score.notationProjection());
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(const MusicXmlExportService().toMusicXml(saved)),
    );
    final bars = reread.parts.first.measures;
    expect(bars[1].endingStart, [1]);
    expect(bars[2].endingStart, [2]);
    expect(bars[3].rightBarlineType, BarlineType.finalBar);
    expect(ScoreTimelineBuilder.playOrder(bars), [0, 1, 0, 2, 3]);
  });
}
