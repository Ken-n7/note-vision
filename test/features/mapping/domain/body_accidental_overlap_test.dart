import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

DetectionResult study({
  String type = 'accidentalSharp',
  double scale = 1,
  bool slope = false,
  double overlap = 4,
  double verticalError = 0,
  double glyphWidth = 10,
  double? glyphHeight = 20,
  double headWidth = 20,
  bool competingHead = false,
  bool competingGlyph = false,
  bool ordinaryGlyph = false,
  bool fourLines = false,
  bool carry = false,
}) {
  double y(double x, double top) => (top + (slope ? .2 * x : 0)) * scale;
  DetectedSymbol symbol(
    String id,
    String name,
    double x,
    double top,
    double w,
    double? h,
  ) => DetectedSymbol(
    id: id,
    type: name,
    x: x * scale,
    y: y(x + w / 2, top),
    width: w * scale,
    height: h == null ? null : h * scale,
    metadata: name.startsWith('notehead') ? {'noteType': 'quarter'} : null,
  );
  final flat = type == 'accidentalFlat' || type == 'accidentalDoubleFlat';
  final accX = 110 + overlap - glyphWidth;
  final accY = 130 - (glyphHeight ?? 20) * (flat ? .8 : .5) + verticalError;
  return DetectionResult(
    imageId: 'body-overlap',
    staffs: [
      DetectedStaff(
        id: 'staff',
        topY: 85 * scale,
        bottomY: 155 * scale,
        lineYs: (fourLines ? [100, 110, 120, 140] : [100, 110, 120, 130, 140])
            .map((v) => v * scale)
            .toList(),
        offsetXs: slope ? [0, 300 * scale] : [],
        offsetYs: slope ? [0, 60 * scale] : [],
      ),
    ],
    barlines: [DetectedBarline(x: 190 * scale, staffId: 'staff')],
    symbols: [
      symbol('clef', 'clefG', 5, 90, 12, 50),
      symbol('first', 'noteheadBlackInSpace', 50, 116, 12, 8),
      if (ordinaryGlyph) symbol('ordinary', 'accidentalFlat', 85, 114, 10, 20),
      symbol('acc', type, accX, accY, glyphWidth, glyphHeight),
      if (competingGlyph)
        symbol('duplicate', type, accX + 1, accY, glyphWidth, glyphHeight),
      symbol('target', 'noteheadBlackInSpace', 110, 126, headWidth, 8),
      if (competingHead)
        symbol('other-head', 'noteheadBlackInSpace', 110, 126, headWidth, 8),
      symbol('later', 'noteheadBlackInSpace', 155, carry ? 126 : 121, 12, 8),
      symbol('next-bar', 'noteheadBlackInSpace', 220, 126, 12, 8),
    ],
  );
}

void main() {
  const mapper = DetectionToScoreMapperService();
  for (final (type, alter) in [
    ('accidentalSharp', 1),
    ('accidentalFlat', -1),
    ('accidentalNatural', 0),
    ('accidentalDoubleSharp', 2),
    ('accidentalDoubleFlat', -2),
  ]) {
    for (final scale in [.5, 1.0, 2.0]) {
      for (final slope in [false, true]) {
        test('$type attaches once at scale $scale, slope $slope', () {
          final detection = study(type: type, scale: scale, slope: slope);
          final before = jsonEncode(detection.toJson());
          final notes = mapper
              .map(detection)
              .score
              .parts
              .single
              .measures
              .first
              .notes;
          expect(notes.map((n) => n.alter), [null, alter, null]);
          expect(notes[1].step, 'G');
          expect(jsonEncode(detection.toJson()), before);
        });
      }
    }
  }

  for (final (name, detection) in [
    ('excessive overlap', study(overlap: 6)),
    ('wrong pitch level', study(verticalError: 6)),
    ('oversized glyph', study(glyphWidth: 30)),
    ('missing glyph height', study(glyphHeight: null)),
    ('oversized head', study(headWidth: 45)),
    ('competing noteheads', study(competingHead: true)),
    ('competing glyphs', study(competingGlyph: true)),
    ('unresolved staff geometry', study(fourLines: true)),
  ]) {
    test('$name retains ordinary right-of-glyph matching', () {
      final notes = mapper
          .map(detection)
          .score
          .parts
          .single
          .measures
          .first
          .notes;
      expect(notes.singleWhere((n) => n.reviewId == 'target').alter, isNull);
      expect(notes.singleWhere((n) => n.reviewId == 'later').alter, 1);
    });
  }

  test('an existing ordinary binding is not overwritten by an overlap', () {
    final notes = mapper
        .map(study(ordinaryGlyph: true))
        .score
        .parts
        .single
        .measures
        .first
        .notes;
    expect(notes.map((n) => n.alter), [null, -1, 1]);
  });

  test('non-overlapping body association is retained', () {
    final notes = mapper
        .map(study(overlap: -5, verticalError: 15))
        .score
        .parts
        .single
        .measures
        .first
        .notes;
    expect(notes.map((n) => n.alter), [null, 1, null]);
  });

  test('overlap alignment follows the refined pitch head', () {
    final original = study();
    final detection = DetectionResult.fromJson({
      ...original.toJson(),
      'symbols': original.symbols.map((symbol) {
        return (symbol.id == 'target'
                ? symbol.copyWith(
                    metadata: {
                      ...?symbol.metadata,
                      DetectedSymbol.pitchBoxKey: [110, 111, 130, 119],
                    },
                  )
                : symbol)
            .toJson();
      }).toList(),
    });
    final notes = mapper.map(detection).score.parts.single.measures.first.notes;
    expect(notes.map((n) => n.alter), [null, null, 1]);
  });

  test('overlap correction carries, resets and survives JSON/XML/playback', () {
    final original = mapper.map(study(carry: true)).score;
    final score = Score.fromJson(jsonDecode(jsonEncode(original.toJson())));
    expect(
      const PlaybackConverter().buildEvents(score).map((e) => e.midiNote),
      [71, 68, 68, 67],
    );
    final xml = XmlDocument.parse(MusicXmlExportService().toMusicXml(score));
    final bars = xml
        .findAllElements('part')
        .first
        .findElements('measure')
        .toList();
    final notes = bars.first.findElements('note').toList();
    expect(notes[1].getElement('accidental')?.innerText, 'sharp');
    expect(notes[2].getElement('accidental'), isNull);
    expect(notes[2].findAllElements('alter').single.innerText, '1');
    expect(
      bars.last.findAllElements('alter').firstOrNull?.innerText ?? '0',
      '0',
    );
  });

  test(
    'sparse photo sharp belongs to the overlapping second E, not the later A',
    () {
      final detection = DetectionResult.fromJson(
        jsonDecode(
          File(
            'test/fixtures/barlines/sparse.detection.json',
          ).readAsStringSync(),
        ),
      );
      final before = jsonEncode(detection.toJson());
      final score = mapper.map(detection).score;
      final notes = score.parts.first.measures[2].notes;
      expect(notes.map((n) => (n.reviewId, n.step, n.alter)), [
        ('symbol-818', 'E', -1),
        ('symbol-819', 'E', 1),
        ('symbol-55', 'A', null),
        ('symbol-820', 'E', null),
      ]);
      final without = DetectionResult.fromJson({
        ...detection.toJson(),
        'symbols': detection.symbols
            .where((s) => s.id != 'symbol-106')
            .map((s) => s.toJson())
            .toList(),
      });
      final control = mapper.map(without).score;
      final actual = score.toJson();
      final symbols =
          (actual['parts'] as List).first['measures'][2]['symbols'] as List;
      (symbols.singleWhere((s) => s['reviewId'] == 'symbol-819') as Map).remove(
        'alter',
      );
      expect(actual, control.toJson());
      expect(jsonEncode(detection.toJson()), before);
    },
  );
}
