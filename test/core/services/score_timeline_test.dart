import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/score_timeline.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';

Score oneBar(List<ScoreSymbol> symbols) => Score(
  id: 'timing',
  title: '',
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
const builder = ScoreTimelineBuilder();

void main() {
  test('sparse timewise parts cannot silently play in the wrong global bar', () {
    for (final sparse in [false, true]) {
      const note =
          '<note><pitch><step>C</step><octave>4</octave></pitch>'
          '<duration>2</duration><type>quarter</type></note>';
      final score = const MusicXmlScoreConverter().convert(
        XmlDocument.parse('''<score-timewise><part-list>
          <score-part id="P1"><part-name>Upper</part-name></score-part>
          <score-part id="P2"><part-name>Lower</part-name></score-part>
          </part-list>
          <measure number="1"><part id="P1">$note</part>
            ${sparse ? '' : '<part id="P2">$note</part>'}</measure>
          <measure number="2"><part id="P1">$note</part><part id="P2">$note</part></measure>
          <measure number="3">${sparse ? '' : '<part id="P1">$note</part>'}
            <part id="P2">$note</part></measure>
          </score-timewise>'''),
      );
      // Both parts have equal counts even in the sparse document. Counts alone
      // cannot detect their different global positions.
      expect(score.parts[0].measures.length, score.parts[1].measures.length);
      if (sparse) {
        expect(
          () => builder.build(Score.fromJson(score.toJson())),
          throwsA(isA<ScoreTimelineException>()),
        );
      } else {
        final timing = builder.build(score);
        expect(
          timing.measures.where((m) => m.measureIndex == 1).map((m) => m.onset),
          [MusicalTime.one, MusicalTime.one],
        );
      }
    }
  });

  test(
    'voices have separate cursors, and chord tones share their base onset',
    () {
      final score = oneBar(const [
        Note(step: 'C', octave: 4, duration: 4, type: 'half', voice: 1),
        Note(
          step: 'E',
          octave: 4,
          duration: 4,
          type: 'half',
          voice: 1,
          isChordTone: true,
        ),
        Note(step: 'G', octave: 4, duration: 4, type: 'half', voice: 1),
        Rest(duration: 2, type: 'quarter', voice: 2),
        Note(
          step: 'A',
          octave: 3,
          duration: 6,
          type: 'half',
          dots: 1,
          voice: 2,
        ),
      ]);
      final timing = builder.measure(score, 0, 0);
      expect(timing.symbols.map((e) => e.onset), [
        MusicalTime.zero,
        MusicalTime.zero,
        MusicalTime(2),
        MusicalTime.zero,
        MusicalTime.one,
      ]);
      expect(timing.duration, MusicalTime(4));
      expect(timing.laneDuration(('2', 1)), MusicalTime(4));
    },
  );

  test(
    'duration capacity considers the edited voice rather than all voices combined',
    () {
      final score = oneBar(const [
        Note(step: 'C', octave: 4, duration: 2, type: 'quarter', voice: 1),
        Rest(duration: 8, type: 'whole', voice: 2),
      ]);
      final state = EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      expect(state.canSetSelectedDuration(wholeDuration), isTrue);
      final edited = state.setSelectedDuration(wholeDuration);
      expect(builder.measure(edited.score, 0, 0).duration, MusicalTime(4));
      expect(edited.applyUndo().score, same(score));
    },
  );

  test(
    'adding to a new voice is allowed even when another voice fills the bar',
    () {
      final score = oneBar(const [Rest(duration: 8, type: 'whole', voice: 1)]);
      final state = EditorState(score: score);
      final added = state.insertSymbolAtMeasureIndex(
        measureIndex: 0,
        insertIndex: 1,
        symbol: const Note(
          step: 'C',
          octave: 4,
          duration: 8,
          type: 'whole',
          voice: 2,
        ),
      );
      expect(added.score.getSymbolAt(0, 0, 1), isA<Note>());
      final blocked = added.insertSymbolAtMeasureIndex(
        measureIndex: 0,
        insertIndex: 2,
        symbol: const Rest(duration: 2, type: 'quarter', voice: 2),
      );
      expect(blocked, same(added));
    },
  );

  test(
    'source edits reflow exact tuplets in their lane without moving another voice',
    () {
      final score = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(
          File(
            'test/musicxml_testfiles/08_polyphonic_preservation.musicxml',
          ).readAsStringSync(),
        ),
      );
      final before = builder.measure(score, 0, 0);
      final note = score.getSymbolAt(0, 0, 2) as Note;
      final json = note.toJson()
        ..['type'] = 'quarter'
        ..['duration'] = 2;
      final edited = score.replaceSymbolAt(0, 0, 2, Note.fromJson(json));
      final after = builder.measure(edited, 0, 0);
      expect(
        after.symbols.firstWhere((e) => e.symbolIndex == 2).duration,
        MusicalTime(2, 3),
      );
      expect(
        after.symbols.firstWhere((e) => e.symbolIndex == 3).onset,
        MusicalTime.one,
      );
      expect(after.symbols.last.onset, before.symbols.last.onset);
      expect(after.symbols.last.duration, before.symbols.last.duration);
      expect(score.musicXmlSource!.events[3].duration, MusicalTime(1, 3));
    },
  );

  test(
    'complex structural changes fail instead of playing stale retained time',
    () {
      final score = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(
          File(
            'test/musicxml_testfiles/08_polyphonic_preservation.musicxml',
          ).readAsStringSync(),
        ),
      );
      final edited = score.deleteSymbolAt(0, 0, 2);
      expect(
        () => builder.build(edited),
        throwsA(isA<ScoreTimelineException>()),
      );
      expect(() => builder.build(score), returnsNormally);
    },
  );

  test(
    'imports migrate to ensemble playback while legacy scans keep reading order',
    () {
      final legacy = oneBar(const [
        Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
      ]);
      expect(
        Score.fromJson(legacy.toJson()).playbackLayout,
        ScorePlaybackLayout.sequentialStaves,
      );
      final imported = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(
          File(
            'test/musicxml_testfiles/08_polyphonic_preservation.musicxml',
          ).readAsStringSync(),
        ),
      );
      expect(
        Score.fromJson(imported.toJson()).playbackLayout,
        ScorePlaybackLayout.simultaneousParts,
      );
      final explicit = imported.copyWith(
        playbackLayout: ScorePlaybackLayout.sequentialStaves,
      );
      expect(
        Score.fromJson(explicit.toJson()).playbackLayout,
        ScorePlaybackLayout.sequentialStaves,
      );
    },
  );

  test(
    'ensemble bar starts align and meter changes can shorten subsequent bars',
    () {
      final score = Score(
        id: 'ensemble',
        title: '',
        composer: '',
        playbackLayout: ScorePlaybackLayout.simultaneousParts,
        parts: [
          for (final p in [0, 1])
            Part(
              id: '$p',
              name: '$p',
              measures: [
                Measure(
                  number: 1,
                  timeSignature: const TimeSignature(beats: 4, beatType: 4),
                  symbols: [
                    Rest(
                      duration: p == 0 ? 8 : 4,
                      type: p == 0 ? 'whole' : 'half',
                    ),
                  ],
                ),
                const Measure(
                  number: 2,
                  timeSignature: TimeSignature(beats: 3, beatType: 4),
                  symbols: [Rest(duration: 2, type: 'quarter')],
                ),
                const Measure(
                  number: 3,
                  symbols: [Rest(duration: 2, type: 'quarter')],
                ),
              ],
            ),
        ],
      );
      final timing = builder.build(score);
      expect(
        timing.measures.where((m) => m.partIndex == 0).map((m) => m.onset),
        [MusicalTime.zero, MusicalTime(4), MusicalTime(7)],
      );
      expect(
        timing.measures.where((m) => m.partIndex == 1).map((m) => m.onset),
        [MusicalTime.zero, MusicalTime(4), MusicalTime(7)],
      );
    },
  );

  test(
    'triplet MIDI boundaries add to exactly one beat without rounding drift',
    () {
      final score = const MusicXmlScoreConverter().convert(
        XmlDocument.parse('''<score-partwise>
    <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>3</divisions></attributes>
    ${[
          for (final step in ['C', 'D', 'E']) '<note><pitch><step>$step</step><octave>4</octave></pitch><duration>1</duration><type>eighth</type></note>',
        ].join()}
    </measure></part></score-partwise>'''),
      );
      final events = const PlaybackConverter().buildEvents(score);
      expect(events.map((e) => e.baseOnsetMs), [0, 167, 333]);
      expect(events.map((e) => e.baseDurationMs), [167, 166, 167]);
      expect(events.last.baseEndMs, 500);
    },
  );
}
