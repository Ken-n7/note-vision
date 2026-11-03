import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_annotation.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/widgets/score_notation/staff_pitch_mapper.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:xml/xml.dart';

/// MuseScore Studio 4.7.5's template each of ours follows.
const museScoreTemplates = {
  'Treble clef': '01-Treble_Clef',
  'Bass clef': '02-Bass_Clef',
  'Grand staff': '03-Grand_Staff',
  'SATB': '01-SATB',
  'SATB + Piano': '03-SATB_+_Piano',
  'Voice + Piano': '07-Voice_+_Piano',
  'String quartet': '01-String_Quartet',
  'Wind quartet': '02-Wind_Quartet',
  'Wind quintet': '03-Wind_Quintet',
  'Saxophone quartet': '04-Saxophone_Quartet',
  'Brass quartet': '05-Brass_Quartet',
  'Brass quintet': '06-Brass_Quintet',
  'Rock band': '01-Rock_Band',
  'Guitar': '01-Guitar',
  'Piano': '04-Piano',
  'Lead sheet': '01-Jazz_Lead_Sheet',
};

/// Each part's name, MIDI program, staves' clefs, transposition and written
/// key, as MusicXML gives them.
List<String> staffFacts(XmlDocument doc) => [
  for (final sp in doc.findAllElements('score-part'))
    () {
      final id = sp.getAttribute('id');
      final first = doc
          .findAllElements('part')
          .firstWhere((p) => p.getAttribute('id') == id)
          .findAllElements('measure')
          .first;
      String? text(XmlElement? e, String name) =>
          e?.getElement(name)?.innerText;
      final clefs = [
        for (final c in first.findAllElements('clef'))
          '${text(c, 'sign')}${text(c, 'line')}'
              '${text(c, 'clef-octave-change') ?? ''}',
      ];
      final t = first.findAllElements('transpose').firstOrNull;
      return '${sp.getElement('part-name')!.innerText} '
          'program=${sp.findAllElements('midi-program').firstOrNull?.innerText} '
          'clefs=${clefs.join(',')} '
          'key=${first.findAllElements('fifths').firstOrNull?.innerText} '
          'transpose=${t == null ? '-' : '${text(t, 'diatonic')}/${text(t, 'chromatic')}/${text(t, 'octave-change') ?? 0}'}';
    }(),
];

NewScoreOptions options(String template, {int pickup = 0, double? tempo}) =>
    NewScoreOptions(
      staves: scoreTemplates.firstWhere((t) => t.name == template).staves,
      title: 'Song',
      fifths: -2,
      time: const TimeSignature(beats: 3, beatType: 4),
      bars: 8,
      pickupBeats: pickup,
      tempo: tempo,
    );

void main() {
  test('every template has a MuseScore counterpart', () {
    expect({
      for (final t in scoreTemplates) t.name,
    }, museScoreTemplates.keys.toSet());
  });

  for (final template in scoreTemplates) {
    test('${template.name} has MuseScore\'s staves, clefs and sounds', () {
      final ours = const MusicXmlExportService().toMusicXml(
        buildNewScore(NewScoreOptions(staves: template.staves), id: 'x'),
      );
      final reference = File(
        'test/musescore_parity/reference/templates/'
        '${museScoreTemplates[template.name]}.musicxml',
      ).readAsStringSync();
      expect(
        staffFacts(XmlDocument.parse(ours)),
        staffFacts(XmlDocument.parse(reference)),
      );
    });
  }

  test('a new score has the key, meter, bars, pickup and tempo asked for', () {
    final score = buildNewScore(
      options('SATB + Piano', pickup: 1, tempo: 96),
      id: 'x',
    );
    // Soprano, Alto, Tenor, Bass and the piano's two staves.
    expect(score.parts.map((p) => (p.name, p.staff)), [
      ('Soprano', 1),
      ('Alto', 1),
      ('Tenor', 1),
      ('Bass', 1),
      ('Piano', 1),
      ('Piano', 2),
    ]);
    expect(score.playbackLayout, ScorePlaybackLayout.simultaneousParts);
    for (final part in score.parts) {
      expect(part.measures, hasLength(9));
      final pickup = part.measures.first;
      expect(pickup.implicit, isTrue);
      expect(pickup.keySignature?.fifths, -2);
      expect(pickup.timeSignature, const TimeSignature(beats: 3, beatType: 4));
      expect((pickup.symbols.single as Rest).type, 'quarter');
      expect(part.measures.map((m) => m.number), [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    }
    expect(
      score.parts[2].measures.first.clef,
      Clef.fromJson(const {'sign': 'G', 'line': 2, 'octave': -1}),
    );
    final tempo = score.parts.first.measures.first.annotations.single;
    expect(
      (tempo.kind, tempo.perMinute, tempo.tempo),
      (AnnotationKind.tempo, 96, 96),
    );
    expect(score.parts[1].measures.first.annotations, isEmpty);
    // Plays: the pickup's rest, then nothing; and saves.
    expect(const PlaybackConverter().buildEvents(score), isNotEmpty);
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.notationProjection(), score.notationProjection());
  });

  test('compound time counts its tempo in dotted quarters', () {
    final six = NewScoreOptions(
      staves: scoreTemplates.first.staves,
      time: const TimeSignature(beats: 6, beatType: 8),
      tempo: 60,
    );
    expect(six.tempoUnit, ('quarter', 1));
    expect(six.pickupChoices, [1, 2, 3, 4]);
    final tempo = buildNewScore(
      six,
    ).parts.first.measures.first.annotations.single;
    expect(tempo.tempo, 90); // quarters per minute
  });

  test('an octave clef writes notes an octave above where they sound', () {
    int offset(String step, int octave, String sign) =>
        StaffPitchMapper.offsetFromBottomLine(
          step: step,
          octave: octave,
          clefSign: sign,
        );
    const tenor = Clef(sign: 'G', line: 2, octave: -1);
    expect(tenor.layoutSign, 'G-1');
    expect(offset('C', 4, tenor.layoutSign), offset('C', 5, 'G'));
  });

  test('an octave clef survives MusicXML export and import', () {
    final xml = const MusicXmlExportService().toMusicXml(
      buildNewScore(options('Guitar'), id: 'x'),
    );
    expect(xml, contains('<clef-octave-change>-1</clef-octave-change>'));
    final reread = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(xml),
    );
    expect(reread.parts.single.measures.first.clef?.octave, -1);
  });
}
