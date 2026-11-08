import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/mapping/domain/internal/signature_inferrer.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

DetectionResult study({
  String accidental = 'accidentalFlat',
  double noteY = 115,
  double? accidentalY,
  double gap = -3,
  double scale = 1,
  bool slope = false,
  bool clefAnchor = false,
  bool timeAnchor = false,
  bool group = false,
  bool firstRest = false,
  bool competingHead = false,
  String clef = 'clefG',
}) {
  double y(double x, double value) => (value + (slope ? x * .2 : 0)) * scale;
  DetectedSymbol symbol(
    String id,
    String type,
    double x,
    double top,
    double w,
    double h,
  ) => DetectedSymbol(
    id: id,
    type: type,
    x: x * scale,
    y: y(x + w / 2, top),
    width: w * scale,
    height: h * scale,
    metadata: type.startsWith('notehead') ? {'noteType': 'quarter'} : null,
  );
  final flat = accidental == 'accidentalFlat';
  final accX = 110 - gap - 10;
  return DetectionResult(
    imageId: 'leading-accidental',
    staffs: [
      DetectedStaff(
        id: 'staff',
        topY: 90 * scale,
        bottomY: 155 * scale,
        lineYs: [100, 110, 120, 130, 140].map((v) => v * scale).toList(),
        offsetXs: slope ? [0, 300 * scale] : [],
        offsetYs: slope ? [0, 60 * scale] : [],
      ),
    ],
    barlines: [
      DetectedBarline(x: 80 * scale, staffId: 'staff'),
      DetectedBarline(x: 200 * scale, staffId: 'staff'),
    ],
    symbols: [
      symbol('clef', clef, 5, 90, 12, 50),
      symbol('key-f', 'accidentalSharp', 28, 95, 8, 20),
      symbol('key-c', 'accidentalSharp', 40, 110, 8, 20),
      symbol('opening-note', 'noteheadBlackInSpace', 60, 116, 12, 8),
      if (clefAnchor) symbol('new-clef', clef, 82, 90, 12, 50),
      symbol(
        'accidental',
        accidental,
        accX,
        accidentalY ?? noteY - (flat ? 16 : 10),
        10,
        20,
      ),
      if (group) symbol('second-key-glyph', accidental, accX - 12, 110, 8, 20),
      if (timeAnchor) ...[
        symbol('meter-top', 'timeSig4', 95, 100, 8, 15),
        symbol('meter-bottom', 'timeSig4', 95, 121, 8, 15),
      ],
      if (firstRest) symbol('rest', 'restQuarter', 95, 118, 8, 15),
      symbol('first-note', 'noteheadBlackInSpace', 110, noteY - 4, 12, 8),
      if (competingHead)
        symbol('other-head', 'noteheadBlackInSpace', 110, noteY - 4, 12, 8),
      symbol('next-note', 'noteheadBlackInSpace', 155, noteY - 4, 12, 8),
      symbol('next-bar-note', 'noteheadBlackInSpace', 220, 111, 12, 8),
    ],
  );
}

void main() {
  const mapper = DetectionToScoreMapperService();
  for (final scale in [.5, 1.0, 2.0]) {
    for (final slope in [false, true]) {
      test(
        'attached C-flat remains on the first note at scale $scale, slope $slope',
        () {
          final detection = study(scale: scale, slope: slope);
          final before = jsonEncode(detection.toJson());
          final score = mapper.map(detection).score;
          expect(
            score.parts.single.measures.map((m) => m.keySignature?.fifths),
            [2, 2, 2],
          );
          expect(score.parts.single.measures[1].notes.map((n) => n.alter), [
            -1,
            null,
          ]);
          expect(
            const PlaybackConverter()
                .buildEvents(score)
                .where((e) => e.measureIndex > 0)
                .map((e) => e.midiNote),
            [71, 71, 73],
          );
          expect(jsonEncode(detection.toJson()), before);
        },
      );
    }
  }

  for (final (type, alter) in [
    ('accidentalSharp', 1),
    ('accidentalNatural', 0),
  ]) {
    test('isolated $type before C remains a written accidental', () {
      final score = mapper.map(study(accidental: type)).score;
      expect(score.parts.single.measures.map((m) => m.keySignature?.fifths), [
        2,
        2,
        2,
      ]);
      expect(score.parts.single.measures[1].notes.first.alter, alter);
    });
  }

  test(
    'written flat, sounding pitch, carry and next-bar reset survive JSON/XML',
    () {
      final original = mapper.map(study()).score;
      final score = Score.fromJson(jsonDecode(jsonEncode(original.toJson())));
      final xml = XmlDocument.parse(MusicXmlExportService().toMusicXml(score));
      final bars = xml
          .findAllElements('part')
          .first
          .findElements('measure')
          .toList();
      expect(bars.map((m) => m.findAllElements('fifths').single.innerText), [
        '2',
        '2',
        '2',
      ]);
      expect(
        bars[1]
            .findElements('note')
            .map((n) => n.findAllElements('alter').single.innerText),
        ['-1', '-1'],
      );
      expect(
        bars[1].findElements('note').first.getElement('accidental')?.innerText,
        'flat',
      );
      expect(bars[2].findAllElements('alter').single.innerText, '1');
    },
  );

  test('real single-flat key stays when its B glyph does not attach to F', () {
    final score = mapper.map(study(noteY: 135, accidentalY: 104, gap: 2)).score;
    expect(score.parts.single.measures[1].keySignature?.fifths, -1);
    expect(score.parts.single.measures[1].notes.first.alter, isNull);
  });

  for (final (type, noteY, fifths) in [
    ('accidentalFlat', 120.0, -1),
    ('accidentalSharp', 100.0, 1),
  ]) {
    test('ambiguous $type on its standard key pitch keeps its key reading', () {
      final score = mapper.map(study(accidental: type, noteY: noteY)).score;
      expect(score.parts.single.measures[1].keySignature?.fifths, fifths);
      expect(score.parts.single.measures[1].notes.first.alter, isNull);
    });
  }

  for (final (name, detection) in [
    ('clef anchor', study(clefAnchor: true)),
    ('meter anchor', study(timeAnchor: true)),
    ('key group', study(group: true)),
    ('first rest', study(firstRest: true)),
    ('competing heads', study(competingHead: true)),
    ('wide gap', study(gap: 18)),
    ('excessive overlap', study(gap: -6)),
    ('vertical mismatch', study(accidentalY: 120)),
    (
      'F-natural cancellation',
      study(accidental: 'accidentalNatural', noteY: 100),
    ),
    (
      'B-natural cancellation',
      study(accidental: 'accidentalNatural', noteY: 120),
    ),
    ('unknown clef', study(clef: 'clefUnknown')),
  ]) {
    test('$name does not trigger the continuation-note rule', () {
      final pipeline = mapper.mapWithPipeline(detection);
      final measure = pipeline.measures[1];
      const parser = SignatureInferrer();
      expect(
        parser.leadingNoteAccidental(
          measure,
          parser.collectLeadingSignatureSymbols(measure.symbols),
          clef: name == 'unknown clef' ? null : const Clef(sign: 'G', line: 2),
        ),
        isNull,
      );
    });
  }

  test('bass E-flat attaches to its first note without changing the key', () {
    final score = mapper.map(study(clef: 'clefF')).score;
    final bar = score.parts.single.measures[1];
    expect(bar.keySignature?.fifths, 2);
    expect(
      (bar.notes.first.step, bar.notes.first.octave, bar.notes.first.alter),
      ('E', 3, -1),
    );
    expect(bar.notes.last.alter, isNull);
  });

  test(
    'first-row key inference is unchanged by continuation-note handling',
    () {
      final original = study();
      final detection = DetectionResult.fromJson({
        ...original.toJson(),
        'barlines': [],
        'symbols': original.symbols
            .where(
              (s) => {'accidental', 'first-note', 'next-note'}.contains(s.id),
            )
            .map((s) => s.toJson())
            .toList(),
      });
      final pipeline = mapper.mapWithPipeline(detection);
      final measure = pipeline.measures.single;
      const parser = SignatureInferrer();
      expect(
        parser.leadingNoteAccidental(
          measure,
          parser.collectLeadingSignatureSymbols(measure.symbols),
          clef: const Clef(sign: 'G', line: 2),
        ),
        isNull,
      );
      expect(
        pipeline.result.score.parts.single.measures.single.keySignature?.fifths,
        -1,
      );
    },
  );

  for (final name in ['dense', 'sparse']) {
    test(
      '$name photo flats belong to first notes, with all other note fields preserved',
      () {
        final detection = DetectionResult.fromJson(
          jsonDecode(
            File(
              'test/fixtures/barlines/$name.detection.json',
            ).readAsStringSync(),
          ),
        );
        final before = jsonEncode(detection.toJson());
        final score = mapper.map(detection).score;
        final cases = name == 'dense'
            ? [(0, 2, 'symbol-2', 'C'), (1, 1, 'symbol-208', 'F')]
            : [(0, 2, 'symbol-818', 'E')];
        for (final (part, bar, id, step) in cases) {
          final notes = score.parts[part].measures[bar].notes;
          final note = notes.singleWhere((n) => n.reviewId == id);
          expect(note.step, step);
          expect(note.alter, -1);
          expect(
            score.parts[part].measures[bar].keySignature,
            score.parts[part].measures.first.keySignature,
          );
        }
        // Removing only the two/one labelled accidental detections supplies a
        // control for key inheritance and every remaining reconstructed field.
        final ids = name == 'dense'
            ? {'symbol-51', 'symbol-226'}
            : {'symbol-104'};
        final without = DetectionResult.fromJson({
          ...detection.toJson(),
          'symbols': detection.symbols
              .where((s) => !ids.contains(s.id))
              .map((s) => s.toJson())
              .toList(),
        });
        final control = mapper.map(without).score;
        final actual = score.toJson();
        for (final (part, bar, id, _) in cases) {
          final symbols =
              (actual['parts'] as List)[part]['measures'][bar]['symbols']
                  as List;
          (symbols.singleWhere((s) => s['reviewId'] == id) as Map).remove(
            'alter',
          );
        }
        expect(actual, control.toJson());
        expect(jsonEncode(detection.toJson()), before);
      },
    );
  }
}
