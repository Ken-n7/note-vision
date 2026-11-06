import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';

// Native-prepared photos and frozen local LiteRT detections. Expected missing
// or misclassified digits remain unresolved/misread; these are regression
// baselines, not complete musical ground truth. Do not infer missing meters
// from a neighboring exercise or the notes' beat totals.
void main() {
  const four = TimeSignature(beats: 4, beatType: 4);
  const two = TimeSignature(beats: 2, beatType: 4);
  final cases = <String, ({List<TimeSignature?> meters, int notes, int rests})>{
    'sparse': (meters: [four, ...List.filled(8, null)], notes: 137, rests: 8),
    'ragged': (meters: [four, two, null, null, two, null], notes: 96, rests: 0),
    'mixed': (meters: [two, null, four, four, two, null], notes: 83, rests: 6),
    'bass': (meters: List.filled(7, null), notes: 139, rests: 0),
    'dense': (meters: List.filled(9, null), notes: 174, rests: 8),
    'song': (meters: List.filled(5, null), notes: 92, rests: 12),
    'clefs': (meters: List.filled(8, null), notes: 0, rests: 0),
  };
  for (final entry in cases.entries) {
    final name = entry.key, expected = entry.value;
    test('$name frozen photo reconstructs only its supported meter stacks', () {
      const root = 'test/fixtures/barlines';
      final original = DetectionResult.fromJson(
        jsonDecode(File('$root/$name.detection.json').readAsStringSync()),
      );
      final before = jsonEncode(original.toJson());
      final photo = img.grayscale(
        img.decodeJpg(File('$root/$name.jpg').readAsBytesSync())!,
      );
      final detection = DetectionResult.fromJson({
        ...original.toJson(),
        'barlines': const BarlineFinder()
            .find(photo, original.staffs, original.symbols)
            .map((b) => b.toJson())
            .toList(),
      });
      const mapper = DetectionToScoreMapperService();
      final score = mapper.map(detection).score;
      expect(
        score.parts.map((p) => p.measures.first.timeSignature),
        expected.meters,
      );
      final music = score.parts
          .expand((p) => p.measures)
          .expand((m) => m.symbols)
          .toList();
      expect(music.whereType<Note>(), hasLength(expected.notes));
      expect(music.whereType<Rest>(), hasLength(expected.rests));
      expect(jsonEncode(original.toJson()), before);
      if (name == 'sparse') {
        expect(score.parts.first.measures.take(3).map((m) => m.timeSignature), [
          four,
          four,
          four,
        ]);
        // Removing the known off-column false 4 must produce exactly the
        // same score as retaining it and selecting the real aligned stack.
        final withoutFalseDigit = DetectionResult.fromJson({
          ...detection.toJson(),
          'symbols': detection.symbols
              .where((s) => s.id != 'symbol-2')
              .map((s) => s.toJson())
              .toList(),
        });
        expect(score.toJson(), mapper.map(withoutFalseDigit).score.toJson());
      }
    });
  }
}
