import 'dart:convert';
import 'dart:io';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_schedule.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_annotations.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Score imported(String xml) =>
    const MusicXmlScoreConverter().convert(XmlDocument.parse(xml));
Score fixture() => imported(
  File(
    'test/musescore_parity/cases/12_text_chord_symbols.musicxml',
  ).readAsStringSync(),
);
EditorState at(Score score, int m, [int? n]) => n == null
    ? EditorState(score: score, selectedPartIndex: 0, selectedMeasureIndex: m)
    : EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: m, symbolIndex: n);
Score plain(List<List<ScoreAnnotation>> markings) => Score(
  id: 'text',
  title: 'Text',
  composer: '',
  parts: [
    Part(
      id: 'P1',
      name: 'Voice',
      measures: [
        for (final (i, marks) in markings.indexed)
          Measure(
            number: i + 1,
            timeSignature: const TimeSignature(beats: 4, beatType: 4),
            annotations: marks,
            symbols: const [
              Note(step: 'C', octave: 4, duration: 8, type: 'whole'),
            ],
          ),
      ],
    ),
  ],
);

void main() {
  test(
    'notations survive saving, model-only export and exact beat offsets',
    () {
      final source = fixture();
      final saved = Score.fromJson(
        jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>,
      );
      expect(
        saved.parts.first.measures.first.annotations.map((a) => a.offset),
        [MusicalTime.zero, MusicalTime.zero, MusicalTime(2), MusicalTime(2)],
      );
      final model = Score(
        id: saved.id,
        title: saved.title,
        composer: saved.composer,
        parts: saved.parts,
      );
      final reread = imported(const MusicXmlExportService().toMusicXml(model));
      expect(
        reread.parts.first.measures
            .expand((m) => m.annotations)
            .map((a) => (a.kind, a.offset, a.label)),
        saved.parts.first.measures
            .expand((m) => m.annotations)
            .map((a) => (a.kind, a.offset, a.label)),
      );
    },
  );
  test('adding/removing on empty bars is atomic and preserves context', () {
    final score = Score(
      id: 'empty',
      title: '',
      composer: '',
      parts: const [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [Measure(number: 1, symbols: [])],
        ),
      ],
    );
    final state = at(score, 0),
        mark = ScoreAnnotation(
          kind: AnnotationKind.staffText,
          text: 'dolce',
          offset: MusicalTime(1, 3),
        );
    final edited = state.setAnnotations([mark]);
    expect(edited.undoStack, hasLength(1));
    expect(edited.selectedMeasureIndex, 0);
    expect(edited.setAnnotations([mark]), same(edited));
    expect(
      edited.applyUndo().score.parts.first.measures.first.annotations,
      isEmpty,
    );
    expect(
      edited
          .applyUndo()
          .applyRedo()
          .score
          .parts
          .first
          .measures
          .first
          .annotations
          .single
          .text,
      'dolce',
    );
    expect(
      edited
          .clearAllSymbols()
          .score
          .parts
          .first
          .measures
          .first
          .annotations
          .single
          .text,
      'dolce',
    );
    final reread = imported(
      const MusicXmlExportService().toMusicXml(edited.score),
    );
    expect(
      reread.parts.first.measures.first.annotations.single.offset,
      MusicalTime(1, 3),
    );
  });
  test(
    'annotation edits patch text while retaining unrelated notation and formatting',
    () {
      final xml =
          File(
            'test/musescore_parity/cases/12_text_chord_symbols.musicxml',
          ).readAsStringSync().replaceFirst(
            '<words>dolce</words>',
            '<words font-style="italic">dolce</words><dynamics><p/></dynamics><pedal type="start"/>',
          );
      final score = imported(xml), state = at(score, 0, 2);
      final original = score.parts.first.measures.first.annotations;
      final changed = [
        for (final a in original)
          if (a.text == 'dolce')
            ScoreAnnotation.fromJson({...a.toJson(), 'text': 'cantabile'})
          else
            a,
      ];
      final output = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(
          state.setAnnotations(changed).score,
        ),
      );
      expect(
        output.findAllElements('pedal').single.getAttribute('type'),
        'start',
      );
      expect(output.findAllElements('p'), isNotEmpty);
      expect(
        output
            .findAllElements('words')
            .where((e) => e.innerText == 'cantabile')
            .single
            .getAttribute('font-style'),
        'italic',
      );
      final deleted = state.setAnnotations(
        original.where((a) => a.text != 'dolce').toList(),
      );
      final out2 = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(deleted.score),
      );
      expect(out2.findAllElements('pedal'), hasLength(1));
      expect(out2.findAllElements('p'), isNotEmpty);
      expect(
        out2.findAllElements('words').where((e) => e.innerText == 'dolce'),
        isEmpty,
      );
      final addition = state.setAnnotations([
        ...original,
        ScoreAnnotation(
          kind: AnnotationKind.rehearsal,
          text: 'B',
          offset: MusicalTime(1, 2),
        ),
      ]);
      final reread = imported(
        const MusicXmlExportService().toMusicXml(addition.score),
      );
      expect(
        reread.parts.first.measures.first.annotations.last.offset,
        MusicalTime(1, 2),
      );
    },
  );
  test(
    'source backup/forward and changed divisions retain exact annotation locations',
    () {
      const xml =
          '<score-partwise><part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>3</divisions></attributes><forward><duration>2</duration></forward><direction><direction-type><words>later</words></direction-type><offset>1</offset></direction><backup><duration>2</duration></backup><direction><direction-type><words>early</words></direction-type><offset>1</offset></direction><note><pitch><step>C</step><octave>4</octave></pitch><duration>3</duration><type>quarter</type></note></measure></part></score-partwise>';
      final score = imported(xml);
      final list = score.parts.first.measures.first.annotations;
      expect(list.map((a) => a.offset), [MusicalTime.one, MusicalTime(1, 3)]);
      final changed = at(score, 0).setAnnotations([
        for (final a in list)
          ScoreAnnotation.fromJson({...a.toJson(), 'text': '${a.text}!'}),
      ]);
      final out = imported(
        const MusicXmlExportService().toMusicXml(changed.score),
      );
      expect(
        out.parts.first.measures.first.annotations.map((a) => a.offset),
        list.map((a) => a.offset),
      );
    },
  );
  test(
    'tempo map integrates held-note changes and relative transport speed',
    () {
      final score = plain([
        [
          const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 60),
          ScoreAnnotation(
            kind: AnnotationKind.tempo,
            tempo: 120,
            offset: MusicalTime(2),
          ),
        ],
      ]);
      final plan = const PlaybackConverter().buildPlan(score);
      expect(plan.durationMs, 3000);
      expect(plan.elapsedMs(0, 2000, 120), 3000);
      expect(plan.elapsedMs(0, 2000, 60), 6000);
      expect(plan.elapsedMs(1000, 2000, 120), 1000);
      expect(plan.tempoMap.points.map((p) => p.$1), contains(1000));
    },
  );
  test('tempo follows repeats and markings on another ensemble staff', () {
    final score = plain([
      [const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 60)],
      [const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 120)],
    ]);
    final first = score.parts.first;
    final repeated = score.copyWith(
      parts: [
        Part(
          id: first.id,
          name: first.name,
          measures: [
            first.measures[0].copyWith(
              leftBarlineType: BarlineType.repeatStart,
            ),
            first.measures[1].copyWith(rightBarlineType: BarlineType.repeatEnd),
          ],
        ),
      ],
    );
    final plan = const PlaybackConverter().buildPlan(repeated);
    expect(plan.durationMs, 12000);
    final ensemble = score.copyWith(
      playbackLayout: ScorePlaybackLayout.simultaneousParts,
      parts: [
        Part(
          id: 'P0',
          name: 'Upper',
          measures: [
            for (final m in first.measures) m.copyWith(annotations: []),
          ],
        ),
        first,
      ],
    );
    expect(const PlaybackConverter().buildPlan(ensemble).durationMs, 6000);
  });
  test('scanned lines keep distinct tempo changes in reading order', () {
    final s = plain([
      [const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 60)],
    ]);
    final upper = s.parts.single;
    final lower = Part(
      id: 'P2',
      name: 'Next line',
      measures: [
        upper.measures.single.copyWith(
          annotations: [
            const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 120),
          ],
        ),
      ],
    );
    expect(
      const PlaybackConverter()
          .buildPlan(s.copyWith(parts: [upper, lower]))
          .durationMs,
      6000,
    );
  });

  test('dotted beat metronome imports as quarter-note playback tempo', () {
    final doc = XmlDocument.parse(
      '<direction><direction-type><metronome><beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>80</per-minute></metronome></direction-type></direction>',
    );
    final mark = MusicXmlAnnotations.read(
      doc.rootElement,
      MusicalTime.zero,
      0,
    )!;
    expect(mark.tempo, 120);
    expect(mark.perMinute, 80);
    expect(mark.beatDots, 1);
  });
  test('chords realize common voicings without taking the note highlight', () {
    final score = plain([
      [
        const ScoreAnnotation(
          kind: AnnotationKind.chord,
          chord: ChordSymbol(root: 'F', bass: 'A'),
        ),
      ],
    ]);
    final events = const PlaybackConverter().buildEvents(score);
    expect(events.where((e) => e.isHarmony).map((e) => e.midiNote), [
      45,
      60,
      65,
      69,
    ]);
    final schedule = PlaybackSchedule(events, endMs: 2000);
    expect(events[schedule.primaryAt(0, 0)!].isHarmony, isFalse);
    expect(ChordSymbol.parse('Bbmaj7')!.label, 'Bbmaj7');
    expect(ChordSymbol.parse('C nonsense'), isNull);
  });
  test(
    'transposition moves chord root and slash bass but preserves other text',
    () {
      final score = plain([
        [
          const ScoreAnnotation(
            kind: AnnotationKind.chord,
            chord: ChordSymbol(root: 'F', bass: 'A'),
          ),
          const ScoreAnnotation(kind: AnnotationKind.staffText, text: 'dolce'),
        ],
      ]);
      final result = const Transposer().transpose(
        score,
        const TransposeOptions(mode: TransposeMode.byInterval, interval: 4),
      );
      final marks = result.parts.first.measures.first.annotations;
      expect(marks.first.chord!.label, 'G/B');
      expect(marks.last.text, 'dolce');
    },
  );
  test('modeled text and harmony allow a simple source rhythm rebuild', () {
    final score = fixture();
    expect(score.musicXmlSource!.requiresPreservation, isFalse);
    final edited = at(score, 0, 0).setSelectedDuration(eighthDuration);
    final output = imported(
      const MusicXmlExportService().toMusicXml(edited.score),
    );
    expect(output.parts.first.measures.expand((m) => m.annotations).length, 7);
    expect(
      output.parts.first.measures.first.annotations.last.offset,
      MusicalTime(2),
    );
    expect(
      (output.parts.first.measures.first.symbols.first as Note).type,
      'eighth',
    );
  });
  test('system directions use MusicXML 4 and plain notation stays 3.1', () {
    final system = plain([
      [const ScoreAnnotation(kind: AnnotationKind.systemText, text: 'All')],
    ]);
    final ordinary = plain([[]]);
    expect(
      XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(system),
      ).rootElement.getAttribute('version'),
      '4.0',
    );
    expect(
      XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(ordinary),
      ).rootElement.getAttribute('version'),
      '3.1',
    );
  });
}
