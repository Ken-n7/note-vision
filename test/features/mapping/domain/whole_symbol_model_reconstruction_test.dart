// Reconstruction from the whole-symbol model: one box per note, value in
// metadata['noteType'], no stems/flags/barlines. Measures must split by the
// notes' real beat values, not one beat per symbol.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  const staff = DetectedStaff(
    id: 'staff-1',
    topY: 100,
    bottomY: 140,
    lineYs: [100.0, 110.0, 120.0, 130.0, 140.0],
  );

  DetectedSymbol sym(String type, double x, {String? noteType}) =>
      DetectedSymbol(
        id: 's$x',
        type: type,
        x: x,
        y: 115, // centre on the middle line (B4 in treble)
        width: 10,
        height: 10,
        metadata: noteType == null ? null : {'noteType': noteType},
      );

  test('splits measures by note value and keeps each note type', () {
    final detection = DetectionResult(
      staffs: const [staff],
      symbols: [
        sym('clefG', 10),
        for (var i = 0; i < 8; i++)
          sym('noteheadBlackInSpace', 50.0 + i * 20, noteType: 'eighth'),
        sym('noteheadWholeInSpace', 250, noteType: 'whole'),
        sym('restHalf', 300),
        sym('noteheadHalfInSpace', 350, noteType: 'half'),
      ],
    );

    final result = const DetectionToScoreMapperService().map(detection);
    final measures = result.score.parts.single.measures;

    expect(measures, hasLength(3));
    expect(
      measures[0].symbols.map((s) => (s as Note).type),
      List.filled(8, 'eighth'),
    );
    expect((measures[1].symbols.single as Note).type, 'whole');
    expect((measures[2].symbols[0] as Rest).type, 'half');
    expect((measures[2].symbols[1] as Note).type, 'half');
    expect(
      result.warnings.where((w) => w.contains('stem')),
      isEmpty,
    );
  });
}
