import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';

// Android Bitmap resize/JPEG-82 inputs and frozen B9 v2 A detections. These
// tests replay geometry without inference. Expected barlines were visually
// checked on these practice photos; they are not full musical ground truth.
const _root = 'test/fixtures/barlines';

List<String?> _ids(Score score) => [
  for (final p in score.parts)
    for (final m in p.measures)
      for (final s in m.symbols)
        if (s is Note) s.reviewId else if (s is Rest) s.reviewId,
];

void main() {
  final expected =
      jsonDecode(File('$_root/boundaries.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final name in ['bass', 'mixed', 'dense']) {
    test('$name real photo keeps its staff-specific written boundaries', () {
      final photo = img.grayscale(
        img.decodeJpg(File('$_root/$name.jpg').readAsBytesSync())!,
      );
      final original = DetectionResult.fromJson(
        jsonDecode(File('$_root/$name.detection.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final beforeJson = jsonEncode(original.toJson());
      final lines = const BarlineFinder().find(
        photo,
        original.staffs,
        original.symbols,
      );
      final expectedRows = expected[name] as List;
      expect(original.staffs, hasLength(expectedRows.length));
      for (final (p, staff) in original.staffs.indexed) {
        final actual = lines
            .where((b) => b.staffId == staff.id)
            .map((b) => b.x)
            .toList();
        final xs = expectedRows[p] as List;
        expect(actual, hasLength(xs.length), reason: '$name row ${p + 1}');
        for (var i = 0; i < xs.length; i++) {
          expect(
            actual[i],
            closeTo((xs[i] as num).toDouble(), 2.5),
            reason: '$name row ${p + 1}',
          );
        }
      }
      expect(jsonEncode(original.toJson()), beforeJson);
      const mapper = DetectionToScoreMapperService();
      final before = mapper.map(original).score;
      final after = mapper
          .map(
            DetectionResult(
              staffs: original.staffs,
              symbols: original.symbols,
              barlines: lines,
            ),
          )
          .score;
      // Repartition existing music; do not drop, reorder or invent symbols.
      expect(_ids(after), _ids(before));
      if (name == 'bass') {
        expect(
          before.parts[1].measures.map(
            (m) => m.symbols.whereType<Note>().length,
          ),
          [1, 2, 17],
        );
        expect(
          after.parts[1].measures.map(
            (m) => m.symbols.whereType<Note>().length,
          ),
          [3, 8, 9],
        );
        expect(
          after.parts[0].measures.map(
            (m) => m.symbols.whereType<Note>().length,
          ),
          [5, 9, 8],
        );
        expect(
          after.parts[2].measures.map(
            (m) => m.symbols.whereType<Note>().length,
          ),
          [7, 8, 9],
        );
      } else {
        expect(after.toJson(), before.toJson());
      }
    });
  }
}
