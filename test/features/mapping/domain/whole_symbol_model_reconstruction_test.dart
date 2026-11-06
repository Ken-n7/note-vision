// Reconstruction from the whole-symbol model: one box per note, value in
// metadata['noteType'], no separate stems/flags. Without detected barlines,
// preserve the complete row and its explicit note/rest values for review.

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

  DetectedSymbol sym(
    String type,
    double x, {
    String? noteType,
    bool beamed = false,
  }) => DetectedSymbol(
    id: 's$x',
    type: type,
    x: x,
    y: 115, // centre on the middle line (B4 in treble)
    width: 10,
    height: 10,
    metadata: noteType == null
        ? null
        : {'noteType': noteType, if (beamed) 'beamed': true},
  );

  test('keeps explicit mixed values together when barlines are unresolved', () {
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

    expect(measures, hasLength(1));
    expect(measures.single.unresolvedBarlines, isTrue);
    expect(
      measures.single.symbols.take(8).map((s) => (s as Note).type),
      List.filled(8, 'eighth'),
    );
    expect((measures.single.symbols[8] as Note).type, 'whole');
    expect((measures.single.symbols[9] as Rest).type, 'half');
    expect((measures.single.symbols[10] as Note).type, 'half');
    expect(result.warnings.where((w) => w.contains('stem')), isEmpty);
  });

  test('notes the detector found under a beam stay beamed', () {
    final detection = DetectionResult(
      staffs: const [staff],
      symbols: [
        sym('clefG', 10),
        sym('noteheadBlackInSpace', 50, noteType: 'eighth', beamed: true),
        sym('noteheadBlackInSpace', 70, noteType: 'sixteenth', beamed: true),
        sym('noteheadBlackInSpace', 90, noteType: 'eighth'),
      ],
    );

    final notes = const DetectionToScoreMapperService()
        .map(detection)
        .score
        .parts
        .single
        .measures
        .expand((m) => m.symbols)
        .whereType<Note>();
    // The third one has a flag of its own.
    expect(notes.map((n) => n.beamed), [true, true, false]);
  });
}
