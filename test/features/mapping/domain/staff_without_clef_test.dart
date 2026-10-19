// A staff whose clef the model missed (or boxed together with the clef of the
// staff below) used to lose every note: without a clef no pitch can be read.
// It is now read in the clef of the nearest staff that has one.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
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

  /// A 10x10 symbol centred on the middle line of staff [index].
  DetectedSymbol sym(String type, int index, double x, {String? noteType}) =>
      DetectedSymbol(
        id: '$type-$index-$x',
        type: type,
        x: x,
        y: 100.0 + index * 200 + 15,
        width: 10,
        height: 10,
        metadata: noteType == null ? null : {'noteType': noteType},
      );

  List<DetectedSymbol> fourQuarters(int index) => [
        for (var i = 0; i < 4; i++)
          sym('noteheadBlackInSpace', index, 60.0 + i * 30, noteType: 'quarter'),
      ];

  List<String> pitches(result, int part) => [
        for (final measure in result.score.parts[part].measures)
          for (final symbol in measure.symbols)
            if (symbol is Note) '${symbol.step}${symbol.octave}',
      ];

  test('a staff with no clef is read in the clef of the staff above', () {
    final result = const DetectionToScoreMapperService().map(
      DetectionResult(
        staffs: [staffAt(0), staffAt(1), staffAt(2)],
        symbols: [
          sym('clefF', 0, 10),
          ...fourQuarters(0),
          ...fourQuarters(1), // no clef detected on this staff
          sym('clefG', 2, 10),
          ...fourQuarters(2),
        ],
      ),
    );

    // The middle line is D3 in bass clef and B4 in treble clef.
    expect(pitches(result, 0), List.filled(4, 'D3'));
    expect(pitches(result, 1), List.filled(4, 'D3'));
    expect(pitches(result, 2), List.filled(4, 'B4'));
    expect(result.score.parts[1].measures.first.clef?.sign, 'F');
    expect(
      result.warnings,
      contains('Staff 2 has no clef; reading it in the clef of staff 1.'),
    );
  });

  test('the first staff borrows from the staff below it', () {
    final result = const DetectionToScoreMapperService().map(
      DetectionResult(
        staffs: [staffAt(0), staffAt(1)],
        symbols: [
          ...fourQuarters(0),
          sym('clefG', 1, 10),
          ...fourQuarters(1),
        ],
      ),
    );

    expect(pitches(result, 0), List.filled(4, 'B4'));
    expect(pitches(result, 1), List.filled(4, 'B4'));
  });

  test('with no clef anywhere the notes are still left out, with a warning', () {
    final result = const DetectionToScoreMapperService().map(
      DetectionResult(staffs: [staffAt(0)], symbols: fourQuarters(0)),
    );

    expect(pitches(result, 0), isEmpty);
    expect(result.warnings.any((w) => w.contains('No clef detected')), isTrue);
  });
}
