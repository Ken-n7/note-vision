import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/domain/editor_command.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note half(String pitch) => Note(
  step: pitch[0],
  octave: int.parse(pitch.substring(1)),
  duration: 4,
  type: 'half',
);

EditorState bars(List<List<ScoreSymbol>> bars, (int, int) select) =>
    EditorState(
      score: NotationReviewService.ensureIdentity(
        Score(
          id: 's',
          title: 'Ties',
          composer: '',
          parts: [
            Part(
              id: 'P1',
              name: 'Piano',
              measures: [
                for (final (i, symbols) in bars.indexed)
                  Measure(
                    number: i + 1,
                    timeSignature: i == 0
                        ? const TimeSignature(beats: 4, beatType: 4)
                        : null,
                    symbols: symbols,
                  ),
              ],
            ),
          ],
        ),
      ),
    ).selectSymbolAt(
      partIndex: 0,
      measureIndex: select.$1,
      symbolIndex: select.$2,
    );

void main() {
  final music = bars(
    [
      [half('C5'), half('G4')],
      [half('G4'), half('A4')],
    ],
    (0, 1),
  );

  test('+ ties to the next same pitch across a bar line, and again unties', () {
    final tied = EditorCommand.tie.execute(music);
    expect(tied.score.spanners.single.kind, SpannerKind.tie);
    expect(tied.undoStack, hasLength(1));
    // The two G4s now sound as one whole note.
    final events = const PlaybackConverter().buildEvents(tied.score);
    final g = events.where((e) => e.midiNote == 67).toList();
    expect([for (final e in g) e.baseDurationMs], [2000]);
    expect(events.where((e) => !e.isRest), hasLength(3));

    expect(EditorCommand.tie.execute(tied).score.spanners, isEmpty);
    // C5 is followed by G4: nothing to tie to.
    final c = music.selectSymbolAt(
      partIndex: 0,
      measureIndex: 0,
      symbolIndex: 0,
    );
    expect(EditorCommand.tie.unavailableReason(c), isNotNull);
  });

  test('S slurs a range or the next note; the same slur toggles off', () {
    final range = music
        .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0)
        .extendSelection(1)
        .extendSelection(1)
        .extendSelection(1);
    final slurred = EditorCommand.slur.execute(range);
    final slur = slurred.score.spanners.single;
    final notes = [
      for (final m in music.score.parts.single.measures)
        for (final s in m.symbols) (s as Note).reviewId,
    ];
    expect((slur.from, slur.to), (notes.first, notes.last));
    expect(slurred.hasRange, isTrue);
    expect(EditorCommand.slur.execute(slurred).score.spanners, isEmpty);

    final next = EditorCommand.slur.execute(music);
    expect(next.score.spanners.single.to, notes[2]);
    final beforeRest = bars(
      [
        [half('C5'), const Rest(duration: 4, type: 'half')],
      ],
      (0, 0),
    );
    expect(EditorCommand.slur.unavailableReason(beforeRest), isNotNull);
  });

  test('note input + writes a tied note of the same pitch', () {
    final state = bars(
      [
        [half('E5')],
      ],
      (0, 0),
    ).enterTiedNote(halfDuration);
    final symbols = state.score.parts.single.measures.single.symbols;
    expect([for (final s in symbols) (s as Note).pitch], ['E5', 'E5']);
    final tie = state.score.spanners.single;
    expect(
      (tie.from, tie.to),
      ((symbols[0] as Note).reviewId, (symbols[1] as Note).reviewId),
    );
    expect(state.selectedSymbolIndex, 1);
    expect(state.undoStack, hasLength(1));
  });

  test('a tie added to an imported file is exported, not dropped', () {
    final imported = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(music.score),
      ),
    );
    final notes = [
      for (final m in imported.parts.single.measures)
        for (final s in m.symbols) (s as Note).reviewId!,
    ];
    final tied = imported.copyWith(
      spanners: [Spanner(SpannerKind.tie, notes[1], notes[2])],
    );
    expect(const MusicXmlExportService().toMusicXml(tied), contains('<tie '));
  });

  test('ties and slurs survive saving and a MusicXML round trip', () {
    final state = EditorCommand.slur.execute(EditorCommand.tie.execute(music));
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(state.score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.spanners, state.score.spanners);
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(const MusicXmlExportService().toMusicXml(saved)),
    );
    expect(
      [for (final s in reread.spanners) s.kind]
        ..sort((a, b) => a.index - b.index),
      [SpannerKind.tie, SpannerKind.slur],
    );
  });
}
