import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note q(String step) =>
    Note(step: step, octave: 4, duration: 2, type: 'quarter');

/// A quarter-note pickup, a full 3/4 bar and an empty bar.
EditorState music({
  TimeSignature time = const TimeSignature(beats: 3, beatType: 4),
}) => EditorState(
  score: NotationReviewService.ensureIdentity(
    Score(
      id: 's',
      title: 'Bars',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Piano',
          measures: [
            Measure(number: 1, timeSignature: time, symbols: [q('G')]),
            Measure(number: 2, symbols: [q('C'), q('D'), q('E')]),
            Measure(number: 3, symbols: const []),
          ],
        ),
      ],
    ),
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);

Score roundTrip(Score score) {
  final saved = Score.fromJson(
    jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
  );
  return const MusicXmlScoreConverter().convert(
    XmlDocument.parse(const MusicXmlExportService().toMusicXml(saved)),
  );
}

void main() {
  test('a pickup is left out of the bar count and survives export', () {
    final s = music().toggleMeasureImplicit();
    expect(s.selectedMeasureImplicit, isTrue);
    expect(
      [for (final m in s.score.parts.single.measures) m.number],
      [0, 1, 2],
    );
    final xml = const MusicXmlExportService().toMusicXml(s.score);
    expect(xml, contains('<measure number="0" implicit="yes">'));
    final reread = roundTrip(s.score).parts.single.measures;
    expect(reread.first.implicit, isTrue);
    expect(reread.map((m) => m.number), [0, 1, 2]);

    // Adding a bar keeps the count; counting the pickup again restores it.
    final added = s
        .selectSymbolAt(partIndex: 0, measureIndex: 1, symbolIndex: 0)
        .addMeasureAfterSelected();
    expect(added.score.parts.single.measures.map((m) => m.number), [
      0,
      1,
      2,
      3,
    ]);
    final counted = s.toggleMeasureImplicit();
    expect(counted.score.parts.single.measures.map((m) => m.number), [1, 2, 3]);
    expect(counted.undoStack, hasLength(2));
  });

  test('a bar rest fills an empty bar and becomes ordinary when changed', () {
    var s = music().copyWith(
      selectedMeasureIndex: 2,
      selectedSymbolIndex: null,
      selectedSymbol: null,
    );
    expect(s.barRestUnavailableReason, isNull);
    s = s.setBarRest();
    final rest = s.score.parts.single.measures[2].symbols.single as Rest;
    expect((rest.measureRest, rest.type, rest.dots), (true, 'half', 1));
    expect(s.barRestUnavailableReason, 'This bar already has a bar rest');
    expect(rest.copyWith(type: 'quarter').measureRest, isFalse);
    expect(rest.copyWith(marks: const []).measureRest, isTrue);

    final xml = const MusicXmlExportService().toMusicXml(s.score);
    expect(xml, contains('<rest measure="yes"/>'));
    final reread = roundTrip(s.score).parts.single.measures[2].symbols.single;
    expect((reread as Rest).measureRest, isTrue);

    final withNotes = s.copyWith(
      selectedMeasureIndex: 1,
      selectedSymbolIndex: null,
      selectedSymbol: null,
    );
    expect(withNotes.barRestUnavailableReason, 'Clear the bar\'s notes first');
  });

  test('common and cut time keep their sign through saving and MusicXML', () {
    for (final time in [TimeSignature.common, TimeSignature.cut]) {
      final s = music(time: time);
      final reread = roundTrip(s.score).parts.single.measures.first;
      expect(reread.timeSignature, time);
      expect(
        reread.timeSignature,
        isNot(TimeSignature(beats: time.beats, beatType: time.beatType)),
      );
    }
  });
}
