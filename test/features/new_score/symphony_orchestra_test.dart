import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/drum_kit.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import 'package:xml/xml.dart';

Score symphony() => buildNewScore(
  NewScoreOptions(
    staves: scoreTemplates
        .firstWhere((t) => t.name == 'Symphony orchestra')
        .staves,
    bars: 2,
  ),
  id: 'symphony',
);

void main() {
  test(
    'imported orchestral kit mix exports without losing its instrument metadata',
    () {
      final source = XmlDocument.parse(
        File(
          'test/musescore_parity/reference/templates/02-Symphony_Orchestra.musicxml',
        ).readAsStringSync(),
      );
      final score = const MusicXmlScoreConverter().convert(source);
      final edited = EditorState(score: score).setPlaybackMix([
        for (final strip in playbackStrips(score))
          strip.percussion
              ? strip.settings.copyWith(program: 40, volume: 55, pan: 12)
              : strip.settings,
      ]).score;
      final exported = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(edited),
      );
      final drums = exported
          .findAllElements('midi-instrument')
          .where((e) => e.getElement('midi-unpitched') != null)
          .toList();
      expect(drums.map((e) => e.getElement('midi-unpitched')!.innerText), [
        '38',
        '39',
        '37',
        '58',
      ]);
      expect(
        drums.map((e) => e.getElement('midi-program')!.innerText),
        everyElement('41'),
      );
      expect(
        drums.map((e) => e.getElement('volume')!.innerText),
        everyElement('55.0'),
      );
      expect(
        drums.map((e) => e.getElement('pan')!.innerText),
        everyElement('12.0'),
      );
      expect(
        exported.findAllElements('midi-device').length,
        source.findAllElements('midi-device').length,
      );
      expect(
        exported.findAllElements('note').map((e) => e.toXmlString()),
        source.findAllElements('note').map((e) => e.toXmlString()),
      );
    },
  );
  test(
    'a large ensemble PDF keeps the title and composer above the notation',
    () {
      final score = symphony().copyWith(
        title: 'Symphony',
        composer: 'Composer',
      );
      final header = const PdfScoreRenderer().debugHeaderLayoutForTesting(
        score,
      );
      expect(header.firstNotationTop, greaterThan(header.headerTextBottom + 4));
    },
  );
  test('symphony has a harp grand staff and three one-line percussion maps', () {
    final score = symphony();
    expect(score.parts, hasLength(26));
    expect(playbackStrips(score), hasLength(25));
    expect(
      score.parts
          .where((p) => p.name == 'Harp')
          .map(
            (p) => (p.staff, p.playback.program, p.measures.first.clef?.sign),
          ),
      [(1, 46, 'G'), (2, 46, 'F')],
    );
    final drums = score.parts.where((p) => p.isPercussion).toList();
    expect(drums.map((p) => p.staffLines), [1, 1, 1]);
    expect(drums.map((p) => p.drums.map((d) => d.key).toList()), [
      [38, 37],
      [36],
      [57],
    ]);
    expect(
      drums.every(
        (p) => p.drums.every(
          (d) => d.step == 'B' && d.octave == 4 && d.voice == 1,
        ),
      ),
      isTrue,
    );
    expect(score.parts[4].measures.first.keySignature?.fifths, 2);
    expect(score.parts[8].measures.first.keySignature?.fifths, 1);
    expect(score.parts[10].measures.first.keySignature?.fifths, 2);
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.toJson(), score.toJson());
    expect(
      saved.parts[16].copyWith(name: 'Side drum').drums.map((d) => d.key),
      [38, 37],
    );
    expect(saved.parts[16].copyWith(name: 'Side drum').singleLine, isTrue);
    final reference = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(
        File(
          'test/musescore_parity/reference/templates/02-Symphony_Orchestra.musicxml',
        ).readAsStringSync(),
      ),
    );
    expect(
      reference.parts
          .where((p) => p.singleLine)
          .map((p) => p.drums.map((d) => d.key).toList()),
      [
        [38, 37],
        [36],
        [57],
      ],
    );
    expect(
      reference.parts.where((p) => p.singleLine).map((p) => p.playback.program),
      [48, 48, 48],
    );
  });

  test(
    'all symphony sounds fit 11 pitched channels plus the orchestral kit',
    () {
      var score = symphony();
      for (var i = 0; i < score.parts.length; i++) {
        final part = score.parts[i];
        final state = EditorState(
          score: score,
        ).copyWith(selectedPartIndex: i, selectedMeasureIndex: 0);
        score =
            (part.isPercussion
                    ? state.enterDrum(part.drums.first, quarterDuration)
                    : state.enterNote('C', quarterDuration))
                .score;
      }
      final mix = PlaybackMix(score, {
        for (var i = 0; i < score.parts.length; i++) i,
      });
      expect(mix.settings, hasLength(12));
      expect(mix.settings[9]?.program, 48);
      expect([mix.channels[16], mix.channels[17], mix.channels[18]], [9, 9, 9]);
      expect(mix.channels[19], mix.channels[20]);
      final xml = XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(score),
      );
      expect(xml.findAllElements('score-part'), hasLength(25));
      expect(xml.findAllElements('staff-lines').map((e) => e.innerText), [
        '1',
        '1',
        '1',
      ]);
      final imported = const MusicXmlScoreConverter().convert(xml);
      for (final current in [score, imported]) {
        final events = const PlaybackConverter()
            .buildEvents(current)
            .where((e) => !e.isRest)
            .toList();
        expect(events, hasLength(26));
        expect(
          events
              .where((e) => [16, 17, 18].contains(e.partIndex))
              .map((e) => e.midiNote),
          [38, 36, 57],
        );
        expect(
          current.parts
              .where((p) => p.singleLine)
              .map((p) => p.playback.program),
          [48, 48, 48],
        );
        expect(current.parts[16].drums.map((d) => d.key), [38, 37]);
      }
    },
  );

  test('snare input uses its map and changing pieces has one undo step', () {
    final before = EditorState(
      score: symphony(),
    ).copyWith(selectedPartIndex: 16, selectedMeasureIndex: 0);
    // A generic kit snare is normalized to this staff's position/voice.
    final entered = before.enterDrum(drumPiece(38)!, quarterDuration);
    final snare = entered.selectedSymbol as Note;
    expect(
      (snare.step, snare.octave, snare.drum, snare.voice ?? 1),
      ('B', 4, 38, 1),
    );
    final changed = entered.setSelectedDrum(drumPiece(37)!);
    final sideStick = changed.selectedSymbol as Note;
    expect(
      (sideStick.step, sideStick.notehead, sideStick.drum),
      ('B', 'x', 37),
    );
    expect((changed.applyUndo().selectedSymbol as Note).drum, 38);
    expect(
      identical(entered.enterDrum(drumPiece(42)!, quarterDuration), entered),
      isTrue,
    );
    expect(drumAt('F', 8, pieces: entered.score.parts[16].drums).key, 38);
    expect(
      drumForShortcut('A', pieces: entered.score.parts[16].drums)?.key,
      37,
    );
    expect(drumForShortcut('C', pieces: entered.score.parts[16].drums), isNull);
  });

  test('adding a percussion staff sets its map; old kits keep five lines', () {
    final oldKit = buildNewScore(
      const NewScoreOptions(
        staves: [NewStaff('Drum Kit', Clef.percussion)],
        bars: 1,
      ),
    );
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(oldKit.toJson())) as Map<String, dynamic>,
    );
    expect(saved.parts.single.staffLines, 5);
    expect(saved.parts.single.drums, drumKit);
    final after = EditorState(score: oldKit).rearrangeParts([
      (from: 0, name: 'Drum Kit', clef: null, joinsPrevious: false),
      (
        from: null,
        name: 'Snare Drum',
        clef: Clef.percussion,
        joinsPrevious: false,
      ),
    ]);
    expect(after.score.parts.last.singleLine, isTrue);
    expect(after.score.parts.last.drums.map((d) => d.key), [38, 37]);
    expect(after.applyUndo().score.parts, hasLength(1));
  });
}
