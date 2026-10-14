// Bars follow the barlines found on each staff, and staves with fewer bars
// are padded so the editor (which pages by measure index) hides none.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/detection/domain/detected_barline.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';

void main() {
  DetectedStaff staffAt(int index) {
    final top = 100.0 + index * 200;
    return DetectedStaff(
      id: 'staff-$index',
      topY: top - 10,
      bottomY: top + 50,
      lineYs: [for (var i = 0; i < 5; i++) top + i * 10],
    );
  }

  DetectedSymbol sym(String type, int staff, double x, {String? noteType}) =>
      DetectedSymbol(
        id: '$type-$staff-$x',
        type: type,
        x: x,
        y: 100.0 + staff * 200 + 15,
        width: 10,
        height: 10,
        metadata: noteType == null ? null : {'noteType': noteType},
      );

  test('each staff is split at its own barlines and all get the same count', () {
    final result = const DetectionToScoreMapperService().map(
      DetectionResult(
        staffs: [staffAt(0), staffAt(1)],
        barlines: const [
          DetectedBarline(x: 150, staffId: 'staff-0'),
          DetectedBarline(x: 250, staffId: 'staff-0'),
          DetectedBarline(x: 200, staffId: 'staff-1'),
        ],
        symbols: [
          sym('clefG', 0, 10),
          // Three notes, then one, then two: not what beat counting would give.
          for (final x in [60.0, 90.0, 120.0])
            sym('noteheadBlackInSpace', 0, x, noteType: 'quarter'),
          sym('noteheadHalfInSpace', 0, 200, noteType: 'half'),
          for (final x in [280.0, 310.0])
            sym('noteheadBlackInSpace', 0, x, noteType: 'quarter'),
          sym('clefG', 1, 10),
          for (final x in [60.0, 300.0])
            sym('noteheadWholeInSpace', 1, x, noteType: 'whole'),
        ],
      ),
    );

    final parts = result.score.parts;
    expect(
      parts[0].measures.map((m) => m.symbols.length),
      [3, 1, 2],
    );
    expect(parts[1].measures.map((m) => m.symbols.length), [1, 1, 0]);
    expect(parts[1].measures.map((m) => m.number), [1, 2, 3]);
  });
}
