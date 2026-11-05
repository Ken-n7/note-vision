import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_annotation.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_mix.dart';
import 'package:note_vision/core/services/transposer.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
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
  'Guitar tablature': '03-Guitar_Tablature',
  'Guitar + tablature': '02-Guitar_+_Tablature',
  'Guitar': '01-Guitar',
  'Piano': '04-Piano',
  'Lead sheet': '01-Jazz_Lead_Sheet',
  'SATB + Organ': '02-SATB_+_Organ',
  'Big band': '02-Big_Band',
  'Jazz combo': '03-Jazz_Combo',
  'Concert band': '01-Concert_Band',
  'Small concert band': '02-Small_Concert_Band',
  'String orchestra': '03-String_Orchestra',
  'Classical orchestra': '01-Classical_Orchestra',
  'Symphony orchestra': '02-Symphony_Orchestra',
};

/// Templates whose MuseScore export loses the written keys.
const legacyKeys = {
  'Big band',
  'Jazz combo',
  'Concert band',
  'Small concert band',
  'Classical orchestra',
  'Symphony orchestra',
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
      // MuseScore escapes an & in a part name twice ("Horn in F 1 &amp; 2");
      // pretty-printed XML writes a name's line break as a space.
      return '${sp.getElement('part-name')!.innerText.replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ')} '
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
      // These template files store written keys in an older form that
      // MuseScore's command-line export drops (it writes C for every part);
      // their keys are checked below instead.
      List<String> facts(String xml) => [
        for (final f in staffFacts(XmlDocument.parse(xml)))
          legacyKeys.contains(template.name)
              ? f.replaceFirst(RegExp(r' key=\S+'), '')
              : f,
      ];
      expect(facts(ours), facts(reference));
    });
  }

  test('a jazz combo in concert C is written as MuseScore\'s template', () {
    final score = buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates.firstWhere((t) => t.name == 'Jazz combo').staves,
      ),
      id: 'x',
    );
    // The template file's keys: trumpet D, alto sax A, tenor sax D.
    expect(
      [for (final p in score.parts) p.measures.first.keySignature?.fifths],
      [2, 3, 2, 0, 0, 0, 0, 0, 0],
    );
  });

  test('classical orchestra keeps two treble horn staves in one instrument', () {
    final score = buildNewScore(
      options('Classical orchestra', pickup: 1),
      id: 'classical',
    );
    expect(score.parts, hasLength(13));
    final horns = score.parts.where((p) => p.name == 'Horns in F').toList();
    expect(horns.map((p) => p.staff), [1, 2]);
    expect(horns.map((p) => p.measures.first.clef), [
      const Clef(sign: 'G', line: 2),
      const Clef(sign: 'G', line: 2),
    ]);
    expect(horns.map((p) => p.squareBracket), [false, true]);
    expect(horns.every((p) => !p.linked), isTrue);
    expect(horns.map((p) => p.transposition?.semitones), [-7, -7]);
    expect(horns.map((p) => p.measures.first.keySignature?.fifths), [-1, -1]);
    final concert = const Transposer().concertPitch(score, true);
    expect(
      concert.parts
          .where((p) => p.name == 'Horns in F')
          .map((p) => p.measures.first.keySignature?.fifths),
      [-2, -2],
    );
    final saved = Score.fromJson(
      jsonDecode(jsonEncode(score.toJson())) as Map<String, dynamic>,
    );
    expect(saved.notationProjection(), score.notationProjection());
    expect(saved.parts[5].copyWith(name: 'Lower horns').squareBracket, isTrue);
    final reference = const MusicXmlScoreConverter().convert(
      XmlDocument.parse(
        File(
          'test/musescore_parity/reference/templates/01-Classical_Orchestra.musicxml',
        ).readAsStringSync(),
      ),
    );
    expect(reference.parts.where((p) => p.squareBracket).map((p) => p.name), [
      'Horns in F',
    ]);
  });

  test(
    'classical orchestra writes the template keys and all sounds fit eight channels',
    () {
      final empty = buildNewScore(
        NewScoreOptions(
          staves: scoreTemplates
              .firstWhere((t) => t.name == 'Classical orchestra')
              .staves,
          bars: 1,
        ),
        id: 'classical',
      );
      // Written keys in MuseScore's template file (its legacy export drops them).
      expect(empty.parts.map((p) => p.measures.first.keySignature?.fifths), [
        0,
        0,
        2,
        0,
        1,
        1,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      final score = empty.copyWith(
        parts: [
          for (final p in empty.parts)
            p.copyWith(
              measures: [
                p.measures.first.copyWith(
                  symbols: [
                    const Note(
                      step: 'C',
                      octave: 4,
                      alter: 0,
                      duration: 2,
                      type: 'quarter',
                    ),
                  ],
                ),
              ],
            ),
        ],
      );
      final mix = PlaybackMix(score, {
        for (var i = 0; i < score.parts.length; i++) i,
      });
      expect(playbackStrips(score), hasLength(12));
      expect(mix.settings.values.map((s) => s.program).toSet(), {
        73,
        68,
        71,
        70,
        60,
        56,
        47,
        48,
      });
      expect(mix.settings, hasLength(8));
      expect(mix.channels[4], mix.channels[5]);
      expect(mix.channels.values, isNot(contains(9)));
      final xml = const MusicXmlExportService().toMusicXml(score);
      final document = XmlDocument.parse(xml);
      final declarations = document.findAllElements('score-part');
      expect(declarations, hasLength(12));
      final hornId = declarations
          .firstWhere(
            (p) => p.getElement('part-name')!.innerText == 'Horns in F',
          )
          .getAttribute('id');
      final hornPart = document.rootElement
          .findElements('part')
          .firstWhere((p) => p.getAttribute('id') == hornId);
      expect(hornPart.findAllElements('staves').single.innerText, '2');
      expect(
        hornPart.findAllElements('part-symbol').single.innerText,
        'square',
      );
      final imported = const MusicXmlScoreConverter().convert(document);
      expect(imported.parts[5].squareBracket, isTrue);
      for (final current in [score, imported]) {
        final events = const PlaybackConverter()
            .buildEvents(current)
            .where((e) => !e.isRest)
            .toList();
        expect(events, hasLength(13));
        expect(
          events
              .where((e) => e.partIndex == 4 || e.partIndex == 5)
              .map((e) => e.midiNote),
          [53, 53],
        );
        expect(events.firstWhere((e) => e.partIndex == 12).midiNote, 48);
      }
    },
  );

  test(
    'moving a horn staff out of its pair removes its square bracket and undo restores it',
    () {
      final before = EditorState(
        score: buildNewScore(options('Classical orchestra'), id: 'classical'),
      );
      final parts = before.score.parts;
      final order = [
        5,
        for (var i = 0; i < parts.length; i++)
          if (i != 5) i,
      ];
      final after = before.rearrangeParts([
        for (final i in order)
          (
            from: i,
            name: parts[i].name,
            clef: null,
            joinsPrevious: parts[i].joinsPrevious,
          ),
      ]);
      expect(after.score.parts.first.staff, 1);
      expect(after.score.parts.first.squareBracket, isFalse);
      expect(after.applyUndo().score.parts[5].squareBracket, isTrue);
    },
  );

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
