import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

EditorState select(List<ScoreSymbol> symbols, {int index = 0}) {
  final score = Score(
    id: 'commands',
    title: 'Study',
    composer: '',
    parts: [
      Part(
        id: 'p1',
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
  );
  return EditorState(
    score: score,
  ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: index);
}

void main() {
  const source = SourceRegion(
    pageId: 'scan',
    x: .1,
    y: .2,
    width: .05,
    height: .1,
  );
  const note = Note(
    step: 'F',
    octave: 4,
    alter: 1,
    duration: 3,
    type: 'quarter',
    dots: 1,
    voice: 2,
    staff: 1,
    confidence: .4,
    reviewId: 'n1',
    source: source,
  );

  test('octave edit preserves rhythm and evidence, with atomic undo/redo', () {
    final initial = select([note]);
    final next = EditorCommand.octaveUp.execute(initial);
    final moved = next.selectedSymbol as Note;
    expect(moved.pitch, 'F#5');
    expect(moved.duration, 3);
    expect(moved.dots, 1);
    expect(moved.voice, 2);
    expect(moved.staff, 1);
    expect(moved.reviewId, 'n1');
    expect(moved.source, same(source));
    expect(moved.confidence, isNull);
    expect(next.undoStack, hasLength(1));
    final undone = EditorCommand.undo.execute(next);
    expect(undone.score, same(initial.score));
    expect(undone.selectedSymbol, same(note));
    expect(undone.hasUnsavedChanges, isFalse);
    expect(
      (EditorCommand.redo.execute(undone).selectedSymbol as Note).pitch,
      'F#5',
    );
  });

  test('octave boundaries are disabled without creating history', () {
    for (final (octave, command) in [
      (1, EditorCommand.octaveDown),
      (7, EditorCommand.octaveUp),
    ]) {
      final state = select([
        Note(step: 'C', octave: octave, duration: 2, type: 'quarter'),
      ]);
      expect(command.unavailableReason(state), contains('pitch range'));
      expect(command.execute(state), same(state));
      expect(state.undoStack, isEmpty);
    }
  });

  test(
    'duration commands respect bar capacity and shrinking remains undoable',
    () {
      final state = select(const [
        Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
        Rest(duration: 6, type: 'half', dots: 1),
      ]);
      expect(EditorCommand.half.unavailableReason(state), contains('room'));
      expect(EditorCommand.half.execute(state), same(state));
      final shorter = EditorCommand.sixteenth.execute(state);
      expect((shorter.selectedSymbol as Note).type, 'sixteenth');
      expect(EditorCommand.undo.execute(shorter).score, same(state.score));
    },
  );

  test(
    'note/rest conversion preserves timing, identity and MusicXML round trip',
    () {
      final state = select([note]);
      final converted = EditorCommand.noteToRest.execute(state);
      final rest = converted.selectedSymbol as Rest;
      expect(rest.duration, note.duration);
      expect(rest.type, note.type);
      expect(rest.dots, note.dots);
      expect(rest.voice, note.voice);
      expect(rest.staff, note.staff);
      expect(rest.reviewId, note.reviewId);
      expect(rest.source, same(source));
      final loaded = Score.fromJson(converted.score.toJson());
      expect(loaded.toJson(), converted.score.toJson());
      final xml = const MusicXmlExportService().toMusicXml(converted.score);
      final imported = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(xml),
      );
      final importedRest = imported.getSymbolAt(0, 0, 0) as Rest;
      expect(importedRest.type, rest.type);
      expect(importedRest.dots, 1);
      expect(importedRest.voice, 2);
      final pitched = EditorCommand.restToNote.execute(converted);
      final restored = pitched.selectedSymbol as Note;
      expect(restored.pitch, 'C4');
      expect(restored.reviewId, 'n1');
      expect(restored.dots, 1);
      expect(EditorCommand.undo.execute(pitched).score, same(converted.score));
      expect(EditorCommand.undo.execute(converted).score, same(state.score));
    },
  );

  test('conversion refuses to detach a chord member or its rhythmic base', () {
    const chord = [
      Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      Note(
        step: 'E',
        octave: 4,
        duration: 2,
        type: 'quarter',
        isChordTone: true,
      ),
    ];
    for (final i in [0, 1]) {
      final state = select(chord, index: i);
      expect(
        EditorCommand.noteToRest.unavailableReason(state),
        contains('chord'),
      );
      expect(EditorCommand.noteToRest.execute(state), same(state));
    }
  });

  test(
    'a rest replacing a beam member repairs the surrounding orphan beams',
    () {
      final symbols = BeamGrouping.join(
        const [
          Note(step: 'C', octave: 4, duration: 1, type: 'eighth'),
          Note(step: 'D', octave: 4, duration: 1, type: 'eighth'),
          Note(step: 'E', octave: 4, duration: 1, type: 'eighth'),
        ],
        0,
        2,
      );
      final initial = select(symbols, index: 1);
      final next = EditorCommand.noteToRest.execute(initial);
      final edited = next.score.parts.first.measures.first.symbols;
      expect(edited[1], isA<Rest>());
      expect(BeamGrouping.groups(edited), isEmpty);
      expect((edited[0] as Note).beamed, isFalse);
      expect((edited[2] as Note).beamed, isFalse);
      expect(EditorCommand.undo.execute(next).score, same(initial.score));
    },
  );

  test(
    'commands reject missing selection and note-only edits reject rests',
    () {
      final noSelection = select([note]).copyWith(clearSelection: true);
      for (final command in EditorCommand.values) {
        expect(command.unavailableReason(noSelection), isNotNull);
        expect(command.execute(noSelection), same(noSelection));
      }
      final rest = select(const [Rest(duration: 2, type: 'quarter')]);
      expect(EditorCommand.octaveUp.execute(rest), same(rest));
      expect(EditorCommand.sharp.execute(rest), same(rest));
      expect(EditorCommand.restToNote.unavailableReason(rest), isNull);
    },
  );
}
