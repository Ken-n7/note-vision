import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note eighth({
  bool beamed = false,
  int? voice,
  bool chord = false,
  int dots = 0,
}) => Note(
  step: 'C',
  octave: 4,
  type: 'eighth',
  duration: 1,
  beamed: beamed,
  voice: voice,
  isChordTone: chord,
  dots: dots,
);
Note sixteenth({Map<int, BeamValue> beams = const {}}) =>
    Note(step: 'D', octave: 4, type: 'sixteenth', duration: 1, beams: beams);
Score scoreOf(List<ScoreSymbol> symbols) => Score(
  id: 'beams',
  title: 'Beams',
  composer: '',
  parts: [
    Part(
      id: 'P1',
      name: 'Staff',
      measures: [
        Measure(
          number: 1,
          timeSignature: const TimeSignature(beats: 4, beatType: 4),
          symbols: symbols,
        ),
      ],
    ),
  ],
);

void main() {
  test('explicit adjacent groups remain distinct in JSON and MusicXML', () {
    final original = List<ScoreSymbol>.generate(4, (_) => eighth());
    var symbols = BeamGrouping.join(original, 0, 1);
    symbols = BeamGrouping.join(symbols, 2, 3);
    expect(BeamGrouping.groups(symbols), [
      [0, 1],
      [2, 3],
    ]);
    final restored = Score.fromJson(scoreOf(symbols).toJson());
    expect(BeamGrouping.groups(restored.parts.single.measures.single.symbols), [
      [0, 1],
      [2, 3],
    ]);
    final xml = const MusicXmlExportService().toMusicXml(scoreOf(symbols));
    final imported = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(BeamGrouping.groups(imported.parts.single.measures.single.symbols), [
      [0, 1],
      [2, 3],
    ]);
    final values = XmlDocument.parse(
      xml,
    ).findAllElements('beam').map((beam) => beam.innerText);
    expect(values, ['begin', 'end', 'begin', 'end']);
  });

  test('legacy beams remain compatible and ignore chord tones', () {
    final symbols = [
      eighth(beamed: true),
      eighth(chord: true),
      eighth(beamed: true),
      const Rest(type: 'eighth', duration: 1),
      eighth(beamed: true),
    ];
    expect(BeamGrouping.groups(symbols), [
      [0, 2],
      [4],
    ]);
    expect(BeamGrouping.valuesFor(symbols, 4), isEmpty);
  });

  test('joining a range detaches it from surrounding legacy groups', () {
    final symbols = List<ScoreSymbol>.generate(6, (_) => eighth(beamed: true));
    final next = BeamGrouping.join(symbols, 2, 3);
    expect(BeamGrouping.groups(next), [
      [0, 1],
      [2, 3],
      [4, 5],
    ]);
    expect(BeamGrouping.groups(symbols), [
      [0, 1, 2, 3, 4, 5],
    ]);
  });

  test('joining across a rest, long note or another voice is rejected', () {
    for (final middle in <ScoreSymbol>[
      const Rest(type: 'eighth', duration: 1),
      const Note(step: 'E', octave: 4, duration: 2, type: 'quarter'),
      eighth(voice: 2),
    ]) {
      final symbols = <ScoreSymbol>[eighth(), middle, eighth()];
      expect(BeamGrouping.canJoin(symbols, 0, 2), isFalse);
      expect(identical(BeamGrouping.join(symbols, 0, 2), symbols), isTrue);
    }
  });

  test('explicit voice boundaries also split old boolean-only beams', () {
    expect(
      BeamGrouping.groups([
        eighth(beamed: true),
        eighth(beamed: true, voice: 2),
      ]),
      [
        [0],
        [1],
      ],
    );
  });

  test('splitting a four-note beam makes two groups without losing notes', () {
    final symbols = BeamGrouping.join(List.generate(4, (_) => eighth()), 0, 3);
    final next = BeamGrouping.split(symbols, 1, before: false);
    expect(BeamGrouping.groups(next), [
      [0, 1],
      [2, 3],
    ]);
    expect(next.length, 4);
    expect(BeamGrouping.groups(BeamGrouping.split(symbols, 2, before: true)), [
      [0, 1],
      [2, 3],
    ]);
  });

  test('a split leaving single notes uses flags instead of orphan beams', () {
    final symbols = BeamGrouping.join([eighth(), eighth()], 0, 1);
    final next = BeamGrouping.split(symbols, 1, before: true);
    expect(BeamGrouping.groups(next), isEmpty);
    expect(next.cast<Note>().every((note) => !note.beamed), isTrue);
  });

  test('separating a middle range keeps both remaining beam groups', () {
    final symbols = BeamGrouping.join(List.generate(6, (_) => eighth()), 0, 5);
    final next = BeamGrouping.separate(symbols, 2, 3);
    expect(BeamGrouping.groups(next), [
      [0, 1],
      [4, 5],
    ]);
    expect((next[2] as Note).beamed, isFalse);
    expect((next[3] as Note).beamed, isFalse);
  });

  for (final (beats, denominator, count, expected) in [
    (
      4,
      4,
      8,
      [
        [0, 1],
        [2, 3],
        [4, 5],
        [6, 7],
      ],
    ),
    (
      6,
      8,
      6,
      [
        [0, 1, 2],
        [3, 4, 5],
      ],
    ),
    (
      3,
      8,
      3,
      [
        [0, 1, 2],
      ],
    ),
    (
      2,
      2,
      8,
      [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
      ],
    ),
  ]) {
    test('group by beat follows $beats/$denominator', () {
      final symbols = BeamGrouping.byBeat(
        List.generate(count, (_) => eighth()),
        TimeSignature(beats: beats, beatType: denominator),
      );
      expect(BeamGrouping.groups(symbols), expected);
    });
  }

  test('dotted eighth plus sixteenth fits one beat and keeps the hook', () {
    final symbols = BeamGrouping.byBeat([
      eighth(dots: 1),
      sixteenth(),
      eighth(),
      eighth(),
    ], const TimeSignature(beats: 4, beatType: 4));
    expect(BeamGrouping.groups(symbols), [
      [0, 1],
      [2, 3],
    ]);
    expect(BeamGrouping.valuesFor(symbols, 1), {
      1: BeamValue.end,
      2: BeamValue.backwardHook,
    });
  });

  test('sixteenths export two beam levels with no extra rhythmic duration', () {
    final symbols = BeamGrouping.join(
      [sixteenth(), sixteenth(), eighth()],
      0,
      2,
    );
    expect(BeamGrouping.valuesFor(symbols, 0), {
      1: BeamValue.begin,
      2: BeamValue.begin,
    });
    expect(BeamGrouping.valuesFor(symbols, 1), {
      1: BeamValue.continueBeam,
      2: BeamValue.end,
    });
    expect(BeamGrouping.valuesFor(symbols, 2), {1: BeamValue.end});
    final xml = const MusicXmlExportService().toMusicXml(scoreOf(symbols));
    expect(xml, contains('<beam number="2">begin</beam>'));
    expect(xml, contains('<beam number="2">end</beam>'));
    final imported = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect((imported.getSymbolAt(0, 0, 1) as Note).beams[2], BeamValue.end);
  });

  test(
    'imported secondary hooks stay separate within a shared primary beam',
    () {
      final symbols = [
        sixteenth(beams: {1: BeamValue.begin, 2: BeamValue.forwardHook}),
        sixteenth(beams: {1: BeamValue.end, 2: BeamValue.backwardHook}),
      ];
      expect(BeamGrouping.groups(symbols, level: 2, within: [0, 1]), [
        [0],
        [1],
      ]);
      expect(BeamGrouping.valuesFor(symbols, 0)[2], BeamValue.forwardHook);
      expect(BeamGrouping.valuesFor(symbols, 1)[2], BeamValue.backwardHook);
    },
  );

  test('group by beat respects rests, chords, and notes crossing a beat', () {
    final symbols = BeamGrouping.byBeat([
      eighth(),
      eighth(chord: true),
      eighth(),
      const Rest(type: 'eighth', duration: 1),
      eighth(),
      eighth(dots: 1),
      eighth(),
    ], const TimeSignature(beats: 4, beatType: 4));
    expect(BeamGrouping.groups(symbols), [
      [0, 2],
    ]);
  });

  test('pickup grouping aligns the short bar to its final beat', () {
    final symbols = BeamGrouping.byBeat(
      [eighth(), eighth(), eighth()],
      const TimeSignature(beats: 4, beatType: 4),
      pickup: true,
    );
    expect(BeamGrouping.groups(symbols), [
      [1, 2],
    ]);
    expect((symbols.first as Note).beamed, isFalse);
  });

  test(
    'an additive meter keeps custom groups until its accent pattern is chosen',
    () {
      final symbols = BeamGrouping.join(
        List.generate(5, (_) => eighth()),
        0,
        2,
      );
      const meter = TimeSignature(beats: 5, beatType: 8);
      expect(BeamGrouping.canGroupByBeat(meter), isFalse);
      expect(identical(BeamGrouping.byBeat(symbols, meter), symbols), isTrue);
    },
  );

  test('applying a preview is one undo step and keeps selection', () {
    final score = scoreOf([eighth(), eighth(), eighth(), eighth()]);
    final original = EditorState(
      score: score,
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 1);
    final next = original.applyBeamEdits(
      BeamGrouping.join(score.parts.single.measures.single.symbols, 0, 3),
    );
    expect(next.undoStack, hasLength(1));
    expect(next.selectedSymbolIndex, 1);
    expect(next.hasUnsavedChanges, isTrue);
    expect(
      BeamGrouping.groups(next.score.parts.single.measures.single.symbols),
      [
        [0, 1, 2, 3],
      ],
    );
    final undone = next.applyUndo();
    expect(
      BeamGrouping.groups(undone.score.parts.single.measures.single.symbols),
      isEmpty,
    );
    expect(
      BeamGrouping.groups(
        undone.applyRedo().score.parts.single.measures.single.symbols,
      ),
      [
        [0, 1, 2, 3],
      ],
    );
  });

  test('pitch, dot, accidental and clef edits retain explicit boundaries', () {
    final symbols = BeamGrouping.join([eighth(), eighth()], 0, 1);
    final original = EditorState(
      score: scoreOf(symbols),
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    for (final edited in [
      original.moveSelectedSymbolUp(),
      original.toggleSelectedDot(),
      original.setSelectedNoteAccidental(1),
      original.setPartClef(const Clef(sign: 'F', line: 4)),
    ]) {
      expect(
        (edited.score.getSymbolAt(0, 0, 0) as Note).beams,
        (symbols.first as Note).beams,
      );
    }
    final quarter = original.setSelectedDuration(quarterDuration);
    expect((quarter.selectedSymbol as Note).beams, isEmpty);
    expect((quarter.selectedSymbol as Note).beamed, isFalse);
  });

  test(
    'checker detects an isolated explicit beam and clears its marks when fixed',
    () {
      final symbols = <ScoreSymbol>[
        eighth().withBeams({1: BeamValue.begin}),
        ...BeamGrouping.join([eighth(), eighth()], 0, 1),
      ];
      final score = scoreOf(symbols);
      final issue = NotationChecker.check(
        score,
      ).where((issue) => issue.message.contains('no note to share')).single;
      final fixed = issue.fix!(score);
      final first = fixed.getSymbolAt(0, 0, 0) as Note;
      expect(first.beamed, isFalse);
      expect(first.beams, isEmpty);
      expect(BeamGrouping.groups(fixed.parts.single.measures.single.symbols), [
        [1, 2],
      ]);
    },
  );

  test('repeating an already applied grouping creates no spurious edit', () {
    final symbols = BeamGrouping.byBeat(
      List.generate(8, (_) => eighth()),
      const TimeSignature(beats: 4, beatType: 4),
    );
    expect(
      identical(
        BeamGrouping.byBeat(
          symbols,
          const TimeSignature(beats: 4, beatType: 4),
        ),
        symbols,
      ),
      isTrue,
    );
  });

  test(
    'deleting a beam partner removes the remaining orphan marks and undo restores them',
    () {
      final symbols = BeamGrouping.join([eighth(), eighth()], 0, 1);
      final state = EditorState(
        score: scoreOf(symbols),
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 1);
      final edited = state.deleteSelectedSymbol();
      final remaining = edited.score.getSymbolAt(0, 0, 0) as Note;
      expect(remaining.beamed, isFalse);
      expect(remaining.beams, isEmpty);
      expect(
        BeamGrouping.groups(
          edited.applyUndo().score.parts.single.measures.single.symbols,
        ),
        [
          [0, 1],
        ],
      );
    },
  );

  test('changing a beamed note to a quarter repairs its former partner', () {
    final state = EditorState(
      score: scoreOf(BeamGrouping.join([eighth(), eighth()], 0, 1)),
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    final edited = state.setSelectedDuration(quarterDuration);
    expect((edited.score.getSymbolAt(0, 0, 1) as Note).beamed, isFalse);
    expect(edited.selectedSymbolIndex, 0);
  });

  test('a new eighth inserted into a beam splits it without orphan marks', () {
    final state = EditorState(
      score: scoreOf(BeamGrouping.join([eighth(), eighth()], 0, 1)),
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    final edited = state.insertSymbolAtMeasureIndex(
      partIndex: 0,
      measureIndex: 0,
      insertIndex: 1,
      symbol: eighth(),
    );
    expect(
      edited.score.parts.single.measures.single.symbols.cast<Note>().every(
        (note) => !note.beamed,
      ),
      isTrue,
    );
    expect(edited.selectedSymbolIndex, 1);
  });

  test(
    'non-rhythmic edits preserve an imported orphan for explicit review',
    () {
      final state = EditorState(
        score: scoreOf([
          eighth().withBeams({1: BeamValue.begin}),
          eighth(),
        ]),
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      expect((state.moveSelectedSymbolUp().selectedSymbol as Note).beams, {
        1: BeamValue.begin,
      });
    },
  );
}
