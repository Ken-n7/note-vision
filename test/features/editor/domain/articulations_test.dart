import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note q(
  String step, {
  List<Articulation> marks = const [],
  bool chord = false,
}) => Note(
  step: step,
  octave: 5,
  duration: 2,
  type: 'quarter',
  marks: marks,
  isChordTone: chord,
);

EditorState bar(List<ScoreSymbol> symbols, {int select = 0, int? fifths}) =>
    EditorState(
      score: Score(
        id: 's',
        title: 'Marks',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Piano',
            measures: [
              Measure(
                number: 1,
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                keySignature: fifths == null
                    ? null
                    : KeySignature(fifths: fifths),
                symbols: symbols,
              ),
            ],
          ),
        ],
      ),
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: select);

List<List<Articulation>> marksOf(EditorState s) => [
  for (final x in s.score.parts.single.measures.single.symbols)
    switch (x) {
      Note(:final marks) || Rest(:final marks) => marks,
      _ => const [],
    },
];

void main() {
  test('a mark toggles on every selected note, chord tones excepted', () {
    final range = bar([
      q('C'),
      q('E', chord: true),
      q('D', marks: [Articulation.staccato]),
      const Rest(duration: 4, type: 'half'),
    ]).extendSelection(1).extendSelection(1);
    final on = EditorCommand.staccato.execute(range);
    expect(marksOf(on), [
      [Articulation.staccato],
      <Articulation>[],
      [Articulation.staccato],
      <Articulation>[],
    ]);
    expect(on.hasRange, isTrue);
    expect(on.undoStack, hasLength(1));
    // Now all have it, so the same command removes it.
    expect(
      marksOf(EditorCommand.staccato.execute(on)).every((m) => m.isEmpty),
      isTrue,
    );
    // Marks keep their canonical order however they were added.
    final both = EditorCommand.staccato.execute(
      EditorCommand.accent.execute(bar([q('C')])),
    );
    expect(marksOf(both).single, [Articulation.staccato, Articulation.accent]);
  });

  test('a fermata goes on a rest; other marks need a note', () {
    final rest = bar([const Rest(duration: 8, type: 'whole')]);
    expect(EditorCommand.staccato.unavailableReason(rest), 'Select a note');
    expect(marksOf(EditorCommand.fermata.execute(rest)).single, [
      Articulation.fermata,
    ]);
  });

  test('marks survive saving and a MusicXML round trip', () {
    final state = EditorCommand.trill.execute(
      EditorCommand.marcato.execute(bar([q('C'), q('D')])),
    );
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(state.score.toJson())) as Map<String, dynamic>,
    );
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(const MusicXmlExportService().toMusicXml(saved)),
    );
    expect((reread.parts.single.measures.single.symbols.first as Note).marks, [
      Articulation.marcato,
      Articulation.trill,
    ]);
  });

  test('staccato shortens the note; a mordent plays the note below', () {
    final plain = bar([
      q('C', marks: [Articulation.staccato]),
    ]);
    expect(
      const PlaybackConverter().buildEvents(plain.score).single.baseDurationMs,
      250,
    );
    // In G major the note below G5 is F#5.
    final mordent = bar([
      const Note(
        step: 'G',
        octave: 5,
        duration: 2,
        type: 'quarter',
        marks: [Articulation.mordent],
      ),
    ], fifths: 1);
    final events = const PlaybackConverter().buildEvents(mordent.score);
    expect([for (final e in events) e.midiNote], [79, 78, 79]);
    expect([for (final e in events) e.baseOnsetMs], [0, 63, 125]);
    expect(events.last.baseEndMs, 500);
  });
}
