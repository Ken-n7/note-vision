import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';

void main() {
  const mapper = DetectionToScoreMapperService();
  const exporter = MusicXmlExportService();

  const staff = DetectedStaff(
    id: 'staff-1',
    topY: 100,
    bottomY: 140,
    lineYs: [100.0, 110.0, 120.0, 130.0, 140.0],
  );

  DetectedSymbol sym({
    required String id,
    required String type,
    required double x,
    required double y,
    double width = 10,
    double height = 8,
  }) => DetectedSymbol(id: id, type: type, x: x, y: y, width: width, height: height);

  DetectionResult buildDetection({List<DetectedSymbol> extraSymbols = const []}) {
    return DetectionResult(
      imageId: 'repeat-test',
      staffs: const [staff],
      barlines: const [DetectedBarline(x: 100, staffId: 'staff-1')],
      symbols: [
        sym(id: 'clef', type: 'clefG', x: 10, y: 92, width: 18, height: 44),
        sym(id: 'note-1', type: 'noteheadBlackOnLine', x: 50, y: 126),
        sym(id: 'stem-1', type: 'stem', x: 58, y: 90, width: 2, height: 42),
        ...extraSymbols,
        sym(id: 'note-2', type: 'noteheadBlackOnLine', x: 130, y: 116),
        sym(id: 'stem-2', type: 'stem', x: 138, y: 80, width: 2, height: 42),
      ],
    );
  }

  group('Repeat barline reconstruction', () {
    test('dots to the left of a barline create an end repeat on the prior measure', () {
      final result = mapper.map(buildDetection(extraSymbols: [
        sym(id: 'dot-1', type: 'repeatDot', x: 92, y: 112, width: 4, height: 4),
        sym(id: 'dot-2', type: 'repeatDot', x: 92, y: 124, width: 4, height: 4),
      ]));

      final measures = result.score.parts.single.measures;
      expect(measures[0].rightBarlineType, BarlineType.repeatEnd);
      expect(measures[1].leftBarlineType, isNull);

      final xml = exporter.toMusicXml(result.score);
      expect(xml, contains('<barline location="right">'));
      expect(xml, contains('<bar-style>light-heavy</bar-style>'));
      expect(xml, contains('<repeat direction="backward"/>'));
    });

    test('dots to the right of a barline create a start repeat on the next measure', () {
      final result = mapper.map(buildDetection(extraSymbols: [
        sym(id: 'dot-1', type: 'repeatDot', x: 104, y: 112, width: 4, height: 4),
        sym(id: 'dot-2', type: 'repeatDot', x: 104, y: 124, width: 4, height: 4),
      ]));

      final measures = result.score.parts.single.measures;
      expect(measures[0].rightBarlineType, isNull);
      expect(measures[1].leftBarlineType, BarlineType.repeatStart);

      final xml = exporter.toMusicXml(result.score);
      expect(xml, contains('<barline location="left">'));
      expect(xml, contains('<bar-style>heavy-light</bar-style>'));
      expect(xml, contains('<repeat direction="forward"/>'));
    });

    test('dots on both sides create end repeat then start repeat across the boundary', () {
      final result = mapper.map(buildDetection(extraSymbols: [
        sym(id: 'left-dot-1', type: 'repeatDot', x: 92, y: 112, width: 4, height: 4),
        sym(id: 'left-dot-2', type: 'repeatDot', x: 92, y: 124, width: 4, height: 4),
        sym(id: 'right-dot-1', type: 'repeatDot', x: 104, y: 112, width: 4, height: 4),
        sym(id: 'right-dot-2', type: 'repeatDot', x: 104, y: 124, width: 4, height: 4),
      ]));

      final measures = result.score.parts.single.measures;
      expect(measures[0].rightBarlineType, BarlineType.repeatEnd);
      expect(measures[1].leftBarlineType, BarlineType.repeatStart);

      final xml = exporter.toMusicXml(result.score);
      expect(xml, contains('<repeat direction="backward"/>'));
      expect(xml, contains('<repeat direction="forward"/>'));
    });

    test('plain barlines remain unchanged when no repeat dots are nearby', () {
      final result = mapper.map(buildDetection());

      final measures = result.score.parts.single.measures;
      expect(measures[0].rightBarlineType, isNull);
      expect(measures[1].leftBarlineType, isNull);

      final xml = exporter.toMusicXml(result.score);
      expect(xml, isNot(contains('<repeat direction=')));
    });
  });
}
