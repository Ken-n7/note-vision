import '../../../support/playback_mix_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:xml/xml.dart';

const flute = PartPlayback(program: 73, volume: 65.5, pan: -30);
Score parse(String xml) =>
    const MusicXmlScoreConverter().convert(XmlDocument.parse(xml));

void main() {
  test('legacy projects keep piano, saved mix survives JSON and undo', () {
    final score = NotationReviewService.ensureIdentity(ensemble());
    final state = EditorState(
      score: score,
    ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
    expect(score.parts.first.playback, const PartPlayback());
    expect(score.parts.first.toJson().containsKey('playback'), false);
    final next = state.setPlaybackMix([
      flute,
      const PartPlayback(mute: true, solo: true),
    ]);
    expect(next.undoStack, hasLength(1));
    expect(next.selectedSymbolIndex, 0);
    final saved = Score.fromJson(jsonDecode(jsonEncode(next.score.toJson())));
    expect(saved.parts.first.playback, flute);
    expect(saved.parts.last.playback.mute, true);
    expect(next.applyUndo().score, same(state.score));
    expect(next.applyUndo().applyRedo().score.parts.first.playback, flute);
    expect(next.setPlaybackMix([flute, saved.parts.last.playback]), same(next));
    expect(
      next.setPlaybackMix([const PartPlayback(program: 128), flute]),
      same(next),
    );
  });
  test('linked staves and sequential scan lines share settings', () {
    final linked = EditorState(
      score: ensemble(linked: true),
    ).setPlaybackMix([flute]);
    expect(linked.score.parts.map((p) => p.playback), everyElement(flute));
    expect(PlaybackMix(linked.score, {0, 1}).channels, {0: 0, 1: 0});
    final scanned = ensemble().copyWith(
      playbackLayout: ScorePlaybackLayout.sequentialStaves,
    );
    expect(playbackStrips(scanned), hasLength(1));
    expect(
      EditorState(
        score: scanned,
      ).setPlaybackMix([flute]).score.parts.last.playback,
      flute,
    );
  });
  test('mute wins over solo and several soloed instruments can sound', () {
    var state = EditorState(score: ensemble(count: 3)).setPlaybackMix([
      flute.copyWith(solo: true, mute: true),
      flute.copyWith(solo: true),
      flute,
    ]);
    expect(PlaybackMix(state.score, {0, 1, 2}).channels.keys, [1]);
    state = state.setPlaybackMix([
      flute.copyWith(solo: true),
      flute.copyWith(solo: true),
      flute,
    ]);
    expect(PlaybackMix(state.score, {0, 1, 2}).channels.keys, [0, 1]);
  });
  test('channel 10 reserved; capacity refuses instead of sharing sounds', () {
    final score = ensemble(count: 16);
    final mix = PlaybackMix(score, {for (var i = 0; i < 15; i++) i});
    expect(mix.settings.keys, isNot(contains(9)));
    expect(mix.settings.keys.last, 15);
    expect(
      () => PlaybackMix(score, {for (var i = 0; i < 16; i++) i}),
      throwsFormatException,
    );
  });
  test(
    'ordinary edits, new bars, scan append and staff reorder retain mix',
    () {
      final s = EditorState(score: ensemble())
          .setPlaybackMix([flute, const PartPlayback(program: 40)])
          .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      expect(s.moveSelectedSymbolUp().score.parts.first.playback, flute);
      expect(s.appendMeasureAtEnd().score.parts.first.playback, flute);
      expect(
        s.score.insertMeasureAfterInAllParts(0).parts.first.playback,
        flute,
      );
      expect(s.score.setMeasureImplicit(0, true).parts.first.playback, flute);
      expect(s.score.appendScore(ensemble()).parts.first.playback, flute);
      expect(s.score.clearAllMusicSymbols().parts.first.playback, flute);
      final changed = s.rearrangeParts([
        (from: 1, name: 'Strings', clef: null, joinsPrevious: false),
        (from: 0, name: 'Woodwind', clef: null, joinsPrevious: false),
        (from: null, name: 'Cello', clef: null, joinsPrevious: false),
      ]);
      expect(changed.score.parts[1].playback, flute);
      expect(changed.score.parts.last.playback.program, 42);
    },
  );
  test('generated MusicXML writes GM programs one based, volume and pan', () {
    final score = EditorState(
      score: ensemble(linked: true),
    ).setPlaybackMix([flute]).score;
    final xml = const MusicXmlExportService().toMusicXml(score);
    final document = XmlDocument.parse(xml);
    expect(document.findAllElements('midi-program').single.innerText, '74');
    expect(document.findAllElements('score-instrument'), hasLength(1));
    expect(parse(xml).parts.map((p) => p.playback), everyElement(flute));
  });
  test('patching sound keeps instrument IDs, devices, metadata and notes', () {
    final source = File(
      'test/musescore_parity/reference/15_ensemble.musicxml',
    ).readAsStringSync();
    final score = parse(source);
    final settings = playbackStrips(score).map((s) => s.settings).toList()
      ..[0] = flute;
    final changed = EditorState(score: score).setPlaybackMix(settings).score;
    final before = XmlDocument.parse(source);
    final after = XmlDocument.parse(
      const MusicXmlExportService().toMusicXml(changed),
    );
    expect(
      after.findAllElements('note').map((n) => n.toXmlString()).toList(),
      before.findAllElements('note').map((n) => n.toXmlString()).toList(),
    );
    expect(
      after.findAllElements('midi-device').map((n) => n.toXmlString()).toList(),
      before
          .findAllElements('midi-device')
          .map((n) => n.toXmlString())
          .toList(),
    );
    expect(
      after
          .findAllElements('score-instrument')
          .map((n) => n.getAttribute('id'))
          .toList(),
      before
          .findAllElements('score-instrument')
          .map((n) => n.getAttribute('id'))
          .toList(),
    );
    expect(parse(after.toXmlString()).parts.first.playback, flute);
    // Project-only flags leave the interoperable sound declaration unchanged.
    final flags = EditorState(score: score).setPlaybackMix([
      for (final s in playbackStrips(score))
        s.settings.copyWith(mute: true, solo: true),
    ]).score;
    expect(
      XmlDocument.parse(
        const MusicXmlExportService().toMusicXml(flags),
      ).toXmlString(),
      before.toXmlString(),
    );
  });
  test('reimported generated instruments still permit a rhythm rebuild', () {
    final score = EditorState(
      score: ensemble(),
    ).setPlaybackMix([flute, const PartPlayback()]).score;
    final imported = parse(const MusicXmlExportService().toMusicXml(score));
    expect(imported.musicXmlSource!.requiresPreservation, false);
    final edited = imported.insertMeasureAfterInAllParts(0);
    final reopened = parse(const MusicXmlExportService().toMusicXml(edited));
    expect(reopened.parts.first.playback, flute);
    expect(reopened.parts.first.measures, hasLength(2));
  });
  test('MuseScore volume and pan survive project and generated export', () {
    final source = File(
      'test/musescore_parity/reference/20_instrument_mix.musicxml',
    ).readAsStringSync();
    final imported = parse(source);
    final saved = Score.fromJson(jsonDecode(jsonEncode(imported.toJson())));
    expect(saved.parts.map((p) => p.playback.program), [73, 42, 0]);
    expect(saved.parts.map((p) => p.playback.midiVolume), [63, 95, 127]);
    expect(saved.parts.map((p) => p.playback.midiPan), [0, 127, 64]);
    final generated = parse(
      const MusicXmlExportService().toMusicXml(
        Score(
          id: saved.id,
          title: saved.title,
          composer: saved.composer,
          parts: saved.parts,
        ),
      ),
    );
    expect(
      generated.parts.map((p) => p.playback),
      saved.parts.map((p) => p.playback),
    );
  });
  test('MusicXML instrument state loads in partwise and timewise scores', () {
    const declaration =
        '<part-list><score-part id="P1"><part-name>Flute</part-name><score-instrument id="I"><instrument-name>Flute</instrument-name></score-instrument><midi-instrument id="I"><midi-program>74</midi-program><volume>65.5</volume><pan>-30</pan></midi-instrument></score-part></part-list>';
    for (final xml in [
      '<score-partwise>$declaration<part id="P1"><measure number="1"/></part></score-partwise>',
      '<score-timewise>$declaration<measure number="1"><part id="P1"/></measure></score-timewise>',
    ]) {
      expect(parse(xml).parts.single.playback, flute);
    }
  });
}
