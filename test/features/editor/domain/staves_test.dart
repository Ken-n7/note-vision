import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

Part part(String id, String name) => Part(
  id: id,
  name: name,
  measures: [
    Measure(
      number: 1,
      clef: const Clef(sign: 'G', line: 2),
      timeSignature: const TimeSignature(beats: 3, beatType: 4),
      keySignature: const KeySignature(fifths: 2),
      symbols: const [
        Note(step: 'D', octave: 5, duration: 6, type: 'half', dots: 1),
      ],
    ),
    const Measure(
      number: 2,
      startsNewSystem: true,
      rightBarlineType: BarlineType.repeatEnd,
      symbols: [],
    ),
  ],
);

void main() {
  const cello = Clef(sign: 'F', line: 4);

  test('a new staff copies the bars and plays with the others', () {
    final state = EditorState(
      score: Score(
        id: 's',
        title: 'T',
        composer: '',
        parts: [part('P1', 'Flute')],
      ),
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    expect(state.score.playbackLayout, ScorePlaybackLayout.sequentialStaves);
    final next = state.rearrangeParts([
      (from: null, name: 'Cello', clef: cello, joinsPrevious: false),
      (from: 0, name: 'Flute', clef: null, joinsPrevious: false),
    ]);
    final added = next.score.parts.first;
    expect((added.id, added.name), ('P2', 'Cello'));
    expect(added.measures.first.clef, cello);
    expect(added.measures.first.timeSignature?.beats, 3);
    expect(added.measures.first.keySignature?.fifths, 2);
    expect(added.measures[1].startsNewSystem, isTrue);
    expect(added.measures[1].rightBarlineType, BarlineType.repeatEnd);
    expect(added.measures.every((m) => m.symbols.isEmpty), isTrue);
    expect(next.score.playbackLayout, ScorePlaybackLayout.simultaneousParts);
    // The selected note moved down with its part.
    expect((next.selectedPartIndex, next.selectedSymbolIndex), (1, 0));
    expect(next.undoStack, hasLength(1));
    expect(identical(next.applyUndo().score, state.score), isTrue);

    final xml = const MusicXmlExportService().toMusicXml(next.score);
    expect('<score-part '.allMatches(xml), hasLength(2));
    expect(xml, contains('<part-name>Cello</part-name>'));
  });

  test('renames, reorders and removes parts in one step', () {
    final state = EditorState(
      score: Score(
        id: 's',
        title: 'T',
        composer: '',
        parts: [part('P1', 'A'), part('P2', 'B'), part('P3', 'C')],
        playbackLayout: ScorePlaybackLayout.simultaneousParts,
      ),
    ).copyWith(selectedPartIndex: 1, selectedMeasureIndex: 1);
    final next = state.rearrangeParts([
      (from: 2, name: 'C', clef: null, joinsPrevious: false),
      (from: 0, name: 'Alto', clef: null, joinsPrevious: false),
    ]);
    expect(
      [for (final p in next.score.parts) (p.id, p.name)],
      [('P3', 'C'), ('P1', 'Alto')],
    );
    // The selected part was removed: the first part keeps bar context.
    expect((next.selectedPartIndex, next.selectedMeasureIndex), (0, 0));
    expect(next.undoStack, hasLength(1));
  });

  test('a piano gets a linked grand staff that exports as one part', () {
    final state = EditorState(
      score: Score(
        id: 's',
        title: 'T',
        composer: '',
        parts: [part('P1', 'Flute')],
      ),
    );
    var next = state.rearrangeParts([
      (from: 0, name: 'Flute', clef: null, joinsPrevious: false),
      (
        from: null,
        name: 'Piano',
        clef: const Clef(sign: 'G', line: 2),
        joinsPrevious: false,
      ),
      (from: null, name: 'Piano', clef: cello, joinsPrevious: true),
    ]);
    expect([for (final p in next.score.parts) p.staff], [1, 1, 2]);
    // Notes written on the lower staff export on staff 2, voice 5.
    next = next
        .copyWith(selectedPartIndex: 2, selectedMeasureIndex: 0)
        .enterNote('C', quarterDuration);
    final xml = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(next.score),
    );
    expect(xml.findAllElements('score-part'), hasLength(2));
    final piano = xml.findAllElements('part').last;
    expect(piano.findAllElements('staves').single.innerText, '2');
    expect(
      [
        for (final c
            in piano.findElements('measure').first.findAllElements('clef'))
          (c.getAttribute('number'), c.findElements('sign').single.innerText),
      ],
      [('1', 'G'), ('2', 'F')],
    );
    final note = piano.findAllElements('note').single;
    expect(note.findElements('staff').single.innerText, '2');
    expect(note.findElements('voice').single.innerText, '5');

    // Moved away from its upper staff, the lower staff stands alone.
    final moved = next.rearrangeParts([
      (from: 2, name: 'Piano', clef: null, joinsPrevious: true),
      (from: 0, name: 'Flute', clef: null, joinsPrevious: false),
      (from: 1, name: 'Piano', clef: null, joinsPrevious: false),
    ]);
    expect([for (final p in moved.score.parts) p.staff], [1, 1, 1]);
  });

  test('scanned staves read in order cannot gain an instrument', () {
    final state = EditorState(
      score: Score(
        id: 's',
        title: 'T',
        composer: '',
        parts: [part('P1', 'Staff 1'), part('P2', 'Staff 2')],
      ),
    );
    expect(state.addStaffBlockedReason, isNotNull);
    final plan = [
      (from: 0, name: 'Staff 1', clef: null, joinsPrevious: false),
      (from: 1, name: 'Staff 2', clef: null, joinsPrevious: false),
      (from: null, name: 'Cello', clef: cello, joinsPrevious: false),
    ];
    expect(identical(state.rearrangeParts(plan), state), isTrue);
    // Renaming is still allowed.
    expect(
      state
          .rearrangeParts([
            (from: 0, name: 'Line 1', clef: null, joinsPrevious: false),
            (from: 1, name: 'Staff 2', clef: null, joinsPrevious: false),
          ])
          .score
          .parts
          .first
          .name,
      'Line 1',
    );
  });
}
