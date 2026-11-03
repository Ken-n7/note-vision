import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

Note note(String step, {int voice = 1, bool chord = false}) => Note(
  step: step,
  octave: 4,
  duration: 2,
  type: 'quarter',
  voice: voice,
  isChordTone: chord,
);
EditorState music() => EditorState(
  score: NotationReviewService.ensureIdentity(
    Score(
      id: 'lyrics',
      title: 'Lyrics',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [
            Measure(
              number: 1,
              symbols: [
                note('C'),
                note('E', chord: true),
                const Rest(duration: 2, type: 'quarter'),
                note('G', voice: 2),
                note('D'),
              ],
            ),
            Measure(number: 2, symbols: [note('E'), note('F')]),
          ],
        ),
      ],
    ),
  ),
).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);

void main() {
  test('lyrics keep verses independent, undo and redo, and no-op history', () {
    final initial = music();
    const first = Lyric(text: 'Hap', syllabic: Syllabic.begin);
    final edited = initial
        .setLyric('1', first)
        .setLyric('2', const Lyric(text: 'Good', verse: '2'));
    expect((edited.selectedSymbol as Note).lyrics, hasLength(2));
    expect(identical(edited.setLyric('1', first), edited), isTrue);
    expect(edited.applyUndo().selectedLyric('2'), isNull);
    expect(edited.applyUndo().applyRedo().selectedLyric('2')!.text, 'Good');
    final removed = edited.setLyric('1', null);
    expect(removed.selectedLyric('1'), isNull);
    expect(removed.selectedLyric('2')!.text, 'Good');
    expect(removed.hasUnsavedChanges, isTrue);
  });

  test(
    'entry stays in its voice, skipping rests and chord tones across bars',
    () {
      final first = music();
      final second = first.nextLyricNote(1);
      expect((second.selectedSymbol as Note).step, 'D');
      final third = second.nextLyricNote(1);
      expect((third.selectedMeasureIndex, third.selectedSymbolIndex), (1, 0));
      expect(third.nextLyricNote(-1).selectedSymbolIndex, 4);
      expect(first.nextLyricNote(-1), same(first));
      expect(second.undoStack, isEmpty);
      final otherVoice = first.selectSymbolAt(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 3,
      );
      expect(otherVoice.nextLyricNote(1), same(otherVoice));
    },
  );

  test(
    'word entry skips tied continuations, melisma navigation includes them',
    () {
      final first = music();
      final target = first.nextLyricNote(1).selectedSymbol as Note;
      final withTie = first.copyWith(
        score: first.score.copyWith(
          spanners: [
            Spanner(
              SpannerKind.tie,
              (first.selectedSymbol as Note).reviewId!,
              target.reviewId!,
            ),
          ],
        ),
      );
      expect(withTie.nextLyricNote(1).selectedMeasureIndex, 1);
      expect(
        withTie.nextLyricNote(1, includeTied: true).selectedSymbolIndex,
        4,
      );
    },
  );

  test('rests and chord tones refuse lyric entry', () {
    final s = music();
    for (final index in [1, 2]) {
      final selected = s.selectSymbolAt(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: index,
      );
      expect(selected.lyricUnavailableReason, isNotNull);
      expect(selected.setLyric('1', const Lyric(text: 'word')), same(selected));
    }
  });

  test(
    'legacy JSON has no lyrics; copies and saving preserve every lyric field',
    () {
      final legacy = note('C');
      expect(Note.fromJson(legacy.toJson()).lyrics, isEmpty);
      final state = music().setLyric(
        'chorus',
        const Lyric(
          text: 'Áraw & gabi',
          verse: 'chorus',
          syllabic: Syllabic.middle,
          extend: LyricExtend.start,
          above: true,
        ),
      );
      final score = Score.fromJson(
        jsonDecode(jsonEncode(state.score.toJson())) as Map<String, dynamic>,
      );
      final saved = score.parts.first.measures.first.symbols.first as Note;
      expect(
        saved.lyrics.single.toJson(),
        (state.selectedSymbol as Note).lyrics.single.toJson(),
      );
      expect(saved.copyWith(step: 'D').lyrics, same(saved.lyrics));
      expect(
        state.moveSelectedPitch(1).selectedLyric('chorus')!.text,
        'Áraw & gabi',
      );
      expect(
        state.copySelection()!.bars.first.whereType<Note>().first.lyrics,
        isNotEmpty,
      );
    },
  );

  test(
    'model-only MusicXML keeps syllables, verses and explicit melisma endpoints',
    () {
      final state = music().setLyric(
        '1',
        const Lyric(text: 'Sing', extend: LyricExtend.start),
      );
      final next = state
          .nextLyricNote(1)
          .setLyric('1', const Lyric(text: '', extend: LyricExtend.stop));
      final xml = const MusicXmlExportService().toMusicXml(next.score);
      final imported = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(xml),
      );
      final lyrics = imported.parts.first.measures
          .expand((m) => m.symbols)
          .whereType<Note>()
          .expand((n) => n.lyrics)
          .toList();
      expect(lyrics.map((l) => l.extend), [
        LyricExtend.start,
        LyricExtend.stop,
      ]);
      expect(lyrics.map((l) => l.text), ['Sing', '']);
      final before = const PlaybackConverter().buildEvents(music().score);
      final after = const PlaybackConverter().buildEvents(next.score);
      expect(
        after.map((e) => (e.midiNote, e.baseOnsetMs, e.baseDurationMs)),
        before.map((e) => (e.midiNote, e.baseOnsetMs, e.baseDurationMs)),
      );
    },
  );

  test('editing a lyric patches retained source and keeps rich other verses', () {
    final xml = File('test/musescore_parity/cases/13_lyrics.musicxml')
        .readAsStringSync()
        .replaceFirst(
          '<text>Hap</text>',
          '<text font-style="italic">Hap</text>',
        )
        .replaceFirst(
          '<text>Good</text>',
          '<text font-weight="bold">Good</text><elision> </elision><text>old</text>',
        )
        .replaceFirst(
          '<type>quarter</type>',
          '<type>quarter</type><notations><technical><fingering>3</fingering></technical></notations>',
        );
    final imported = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(imported.musicXmlSource!.requiresPreservation, isTrue);
    final s = EditorState(
      score: imported,
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    final old = s.selectedLyric('1')!;
    final edited = s.setLyric(
      '1',
      Lyric(text: 'Mer', syllabic: old.syllabic, sourceXml: old.sourceXml),
    );
    final output = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(edited.score),
    );
    expect(output.findAllElements('fingering').single.innerText, '3');
    final first = output.findAllElements('note').first;
    final verses = first.findElements('lyric').toList();
    expect(verses.first.getElement('text')!.innerText, 'Mer');
    expect(
      verses.first.getElement('text')!.getAttribute('font-style'),
      'italic',
    );
    expect(
      const PlaybackConverter().buildEvents(edited.score).length,
      const PlaybackConverter().buildEvents(imported).length,
    );
    expect(verses[1].findElements('text').length, 2);
    expect(verses[1].getElement('elision')!.innerText, ' ');
    expect(verses[1].getElement('text')!.getAttribute('font-weight'), 'bold');
    final restored = const MusicXmlScoreConverter().convert(output);
    expect(
      (restored.parts.first.measures.first.symbols.first as Note)
          .lyrics[1]
          .text,
      'Good old',
    );
  });

  test(
    'modeled lyrics permit rhythm edits to rebuild a simple imported file',
    () {
      final imported = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(
          File(
            'test/musescore_parity/cases/13_lyrics.musicxml',
          ).readAsStringSync(),
        ),
      );
      expect(imported.musicXmlSource!.requiresPreservation, isFalse);
      final state = EditorState(score: imported)
          .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0)
          .setSelectedDuration(eighthDuration);
      final output = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(state.score),
      );
      expect(
        output.findAllElements('note').first.getElement('type')!.innerText,
        'eighth',
      );
      expect(output.findAllElements('lyric').length, 7);
    },
  );

  test(
    'generated export keeps unedited rich lyric XML through project saving',
    () {
      const xml =
          '<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type><lyric number="chorus" placement="above" print-object="no"><syllabic>single</syllabic><text font-style="italic">a</text><elision>‿</elision><syllabic>single</syllabic><text>b</text><extend type="continue"/><end-line/></lyric></note></measure></part></score-partwise>';
      final imported = const MusicXmlScoreConverter().convert(
        XmlDocument.parse(xml),
      );
      final saved = Score.fromJson(
        jsonDecode(jsonEncode(imported.toJson())) as Map<String, dynamic>,
      );
      final modelOnly = Score(
        id: saved.id,
        title: saved.title,
        composer: saved.composer,
        parts: saved.parts,
      );
      final exported = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(modelOnly),
      );
      expect(
        exported
            .findAllElements('lyric')
            .single
            .childElements
            .map((e) => e.toXmlString()),
        XmlDocument.parse(xml)
            .findAllElements('lyric')
            .single
            .childElements
            .map((e) => e.toXmlString()),
      );
    },
  );
}
