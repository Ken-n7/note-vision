import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_annotation.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

/// Flute, B♭ clarinet, alto sax, horn in F and tenor sax, each written so
/// it sounds C5 D5 E5 F5.
Score imported() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File(
      'test/musescore_parity/cases/23_transposing.musicxml',
    ).readAsStringSync(),
  ),
);

Map<int, List<int>> sounding(Score score) {
  final byPart = <int, List<int>>{};
  for (final e in const PlaybackConverter().buildEvents(score)) {
    byPart.putIfAbsent(e.partIndex, () => []).add(e.midiNote);
  }
  return byPart;
}

List<String> written(Score score, int part) => [
  for (final n in score.parts[part].measures.first.symbols.cast<Note>())
    n.pitch,
];

void main() {
  test(
    'transposing parts import their interval and sound at concert pitch',
    () {
      final score = imported();
      expect(score.parts.map((p) => p.transposition?.semitones), [
        null,
        -2,
        -9,
        -7,
        -14,
      ]);
      expect(written(score, 1), ['D5', 'E5', 'F5', 'G5']);
      for (final notes in sounding(score).values) {
        expect(notes, [72, 74, 76, 77]);
      }
    },
  );

  test('concert pitch writes every part as it sounds, and back again', () {
    final state = EditorState(score: imported());
    final concert = state.toggleConcertPitch();
    expect(concert.score.concertPitch, isTrue);
    expect(concert.undoStack, hasLength(1));
    for (var p = 0; p < 5; p++) {
      expect(written(concert.score, p), ['C5', 'D5', 'E5', 'F5'], reason: '$p');
      expect(concert.score.parts[p].measures.first.keySignature?.fifths, 0);
    }
    // It sounds the same, saves, and turns back exactly.
    expect(sounding(concert.score), sounding(state.score));
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(concert.score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.concertPitch, isTrue);
    final back = concert.toggleConcertPitch().score;
    expect(back.notationProjection(), state.score.notationProjection());
  });

  test('export from concert pitch writes the players\' parts', () {
    final score = imported();
    final concert = EditorState(score: score).toggleConcertPitch().score;
    final xml = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(concert),
    );
    final reread = const MusicXmlScoreConverter().convert(xml);
    expect(reread.concertPitch, isFalse);
    expect(written(reread, 1), ['D5', 'E5', 'F5', 'G5']);
    expect(reread.parts[4].transposition?.octave, -1);
  });

  test('a clarinet added in B♭ major is written in C major', () {
    final flute = imported().copyWith(
      parts: [
        imported().parts.first.copyWith(
          measures: [
            imported().parts.first.measures.first.withContent(
              keySignature: const KeySignature(fifths: -2),
              symbols: const [],
            ),
          ],
        ),
      ],
    );
    final state = EditorState(score: flute).rearrangeParts([
      (from: 0, name: 'Flute', clef: null, joinsPrevious: false),
      (
        from: null,
        name: 'Clarinet in Bb',
        clef: const Clef(sign: 'G', line: 2),
        joinsPrevious: false,
      ),
    ]);
    final clarinet = state.score.parts.last;
    expect(clarinet.transposition?.chromatic, -2);
    expect(clarinet.measures.first.keySignature?.fifths, 0);
  });

  test('a chord symbol in a transposing part sounds at concert pitch', () {
    // A C chord written for the B♭ clarinet sounds as B♭.
    final score = imported();
    Score withChordIn(int part) => score.copyWith(
      parts: [
        for (final (i, p) in score.parts.indexed)
          i != part
              ? p
              : p.copyWith(
                  measures: [
                    p.measures.first.copyWith(
                      annotations: [
                        ScoreAnnotation(
                          kind: AnnotationKind.chord,
                          chord: ChordSymbol.parse('C'),
                        ),
                      ],
                    ),
                  ],
                ),
      ],
    );
    List<int> chordKeys(Score s) => [
      for (final e in const PlaybackConverter().buildEvents(s))
        if (e.isHarmony) e.midiNote,
    ]..sort();
    final written = chordKeys(withChordIn(1));
    // B♭, D and F.
    expect({for (final k in written) k % 12}, {10, 2, 5});
    final concert = EditorState(
      score: withChordIn(1),
    ).toggleConcertPitch().score;
    expect(
      concert.parts[1].measures.first.annotations.single.chord?.label,
      'Bb',
    );
    expect(chordKeys(concert), written);
  });
}
