import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

EditorState bar(List<ScoreSymbol> symbols, {int select = 0}) => EditorState(
  score: Score(
    id: 's',
    title: 'Tuplets',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: 'Piano',
        measures: [
          Measure(
            number: 1,
            timeSignature: const TimeSignature(beats: 4, beatType: 4),
            symbols: symbols,
          ),
        ],
      ),
    ],
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: select);

const quarterC = Note(step: 'C', octave: 5, duration: 2, type: 'quarter');
const halfRest = Rest(duration: 4, type: 'half');

List<ScoreSymbol> symbols(EditorState s) =>
    s.score.parts.single.measures.single.symbols;

void main() {
  test('Ctrl+3 fills a quarter with a triplet of eighths, as one step', () {
    final state = EditorCommand.triplet.execute(
      bar([quarterC, quarterC, halfRest]),
    );
    final made = symbols(state).take(3).toList();
    expect([for (final s in made) s.runtimeType], [Note, Rest, Rest]);
    expect(
      [
        for (final s in made)
          switch (s) {
            Note(:final type, :final tuplet) ||
            Rest(:final type, :final tuplet) => (type, tuplet),
            _ => null,
          },
      ],
      [
        ('eighth', const Tuplet(3, 2, start: true)),
        ('eighth', const Tuplet(3, 2)),
        ('eighth', const Tuplet(3, 2, stop: true)),
      ],
    );
    expect((made.first as Note).pitch, 'C5');
    expect(state.selectedSymbolIndex, 0);
    expect(state.undoStack, hasLength(1));
    // The bar keeps its length: the triplet takes one beat exactly.
    final timeline = const ScoreTimelineBuilder().measure(state.score, 0, 0);
    expect(timeline.symbols[3].onset, MusicalTime.one);
    expect(timeline.duration, MusicalTime(4));
  });

  test('typing in note input writes over the tuplet rests', () {
    var state = EditorCommand.triplet.execute(
      bar([quarterC, halfRest, halfRest]),
    );
    state = state
        .enterNote('E', quarterDuration)
        .enterNote('G', quarterDuration);
    final made = symbols(state).take(3).cast<Note>().toList();
    expect([for (final n in made) n.pitch], ['C5', 'E5', 'G5']);
    expect(made.last.tuplet, const Tuplet(3, 2, stop: true));
    // The rest of the bar is untouched.
    expect(symbols(state), hasLength(5));
    final events = const PlaybackConverter().buildEvents(state.score);
    // Exact thirds of a beat, rounded at absolute boundaries (no drift).
    expect([for (final e in events.take(4)) e.baseOnsetMs], [0, 167, 333, 500]);
  });

  test('duration and dot checks on a tuplet note time it exactly', () {
    // A half-note triplet member is 4/3 of a beat: no decimal can hold it.
    final state = EditorCommand.triplet.execute(
      bar([const Note(step: 'C', octave: 5, duration: 8, type: 'whole')]),
    );
    expect(state.canSetSelectedDuration(quarterDuration), isTrue);
    expect(state.canSetSelectedDuration(wholeDuration), isFalse);
    expect(state.canToggleSelectedDot, isFalse);
  });

  test('quintuplets, and what cannot become a tuplet', () {
    final five = bar([
      quarterC,
      halfRest,
      const Rest(duration: 2, type: 'quarter'),
    ]).makeTuplet(5);
    expect(symbols(five).take(5).map((s) => (s as dynamic).type).toSet(), {
      'sixteenth',
    });
    expect(
      (symbols(five).first as Note).tuplet,
      const Tuplet(5, 4, start: true),
    );

    final sixteenth = bar([
      const Note(step: 'C', octave: 5, duration: 1, type: 'sixteenth'),
    ]);
    expect(sixteenth.tupletUnavailableReason(3), 'This value is too short');
    final dotted = bar([
      const Note(step: 'C', octave: 5, duration: 3, type: 'quarter', dots: 1),
    ]);
    expect(dotted.tupletUnavailableReason(3), 'Remove the dot first');
    expect(
      EditorCommand.triplet.execute(bar([quarterC])).tupletUnavailableReason(3),
      'This note is already in a tuplet',
    );
  });

  test('tuplets survive saving and export with whole divisions', () {
    final state = EditorCommand.triplet.execute(bar([quarterC, halfRest]));
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(state.score.toJson())) as Map<String, dynamic>,
    );
    expect(
      (saved.parts.single.measures.single.symbols[1] as Rest).tuplet,
      const Tuplet(3, 2),
    );
    final xml = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(saved),
    );
    expect(xml.findAllElements('divisions').single.innerText, '24');
    expect(
      [
        for (final n in xml.findAllElements('note').take(3))
          n.findElements('duration').single.innerText,
      ],
      ['8', '8', '8'],
    );
    expect(xml.findAllElements('time-modification'), hasLength(3));
    expect(xml.findAllElements('tuplet'), hasLength(2));
  });
}
