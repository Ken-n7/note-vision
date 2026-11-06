import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/mapping/domain/internal/mapping_types.dart';
import 'package:note_vision/features/mapping/domain/internal/signature_inferrer.dart';

const _staff = DetectedStaff(
  id: 'staff',
  topY: 90,
  bottomY: 150,
  lineYs: [100, 110, 120, 130, 140],
);

StaffOwnedSymbol _digit(
  String id,
  String digit,
  double x,
  double y, {
  double width = 10,
  double height = 16,
  DetectedStaff staff = _staff,
  double confidence = .8,
}) => StaffOwnedSymbol(
  staff: staff,
  symbol: DetectedSymbol(
    id: id,
    type: 'timeSig$digit',
    x: x - width / 2,
    y: y - height / 2,
    width: width,
    height: height,
    confidence: confidence,
  ),
);

void main() {
  const parser = SignatureInferrer();
  TimeSignature? read(
    List<StaffOwnedSymbol> entries, {
    List<String>? warnings,
    DetectedStaff staff = _staff,
  }) => parser.inferTimeSignature(staff, entries, warnings: warnings ?? []);

  test('reads a single aligned 4/4 stack', () {
    expect(
      read([_digit('top', '4', 60, 110), _digit('bottom', '4', 60, 130)]),
      const TimeSignature(beats: 4, beatType: 4),
    );
  });

  test('an off-column high-confidence 4 does not turn 4/4 into 44/4', () {
    final warnings = <String>[];
    final entries = [
      _digit('false', '4', 30, 110, width: 24, confidence: .99),
      _digit('top', '4', 60, 110, width: 24, confidence: .45),
      _digit('bottom', '4', 66, 135, width: 24),
    ];
    final before = entries.map((e) => e.symbol.toJson()).toList();
    expect(
      read(entries, warnings: warnings),
      const TimeSignature(beats: 4, beatType: 4),
    );
    expect(warnings, isNotEmpty);
    expect(entries.map((e) => e.symbol.toJson()).toList(), before);
  });

  test('reads a centered multi-digit numerator', () {
    expect(
      read([
        _digit('one', '1', 54, 110),
        _digit('two', '2', 66, 110),
        _digit('bottom', '8', 60, 130),
      ]),
      const TimeSignature(beats: 12, beatType: 8),
    );
  });

  test(
    'retains a genuinely centered 44/4 rather than capping the numerator',
    () {
      expect(
        read([
          _digit('first', '4', 54, 110),
          _digit('second', '4', 66, 110),
          _digit('bottom', '4', 60, 130),
        ]),
        const TimeSignature(beats: 44, beatType: 4),
      );
    },
  );

  test('reads a centered multi-digit denominator', () {
    expect(
      read([
        _digit('top', '4', 60, 110),
        _digit('one', '1', 54, 130),
        _digit('six', '6', 66, 130),
      ]),
      const TimeSignature(beats: 4, beatType: 16),
    );
  });

  test('overlapping repeated detections are not concatenated into 44', () {
    expect(
      read([
        _digit('first', '4', 60, 110),
        _digit('repeat', '4', 61, 110),
        _digit('bottom', '4', 60, 130),
      ]),
      const TimeSignature(beats: 4, beatType: 4),
    );
  });

  test('conflicting detections on the same glyph leave meter unresolved', () {
    final warnings = <String>[];
    expect(
      read([
        _digit('three', '3', 60, 110),
        _digit('four', '4', 60, 110),
        _digit('bottom', '4', 60, 130),
      ], warnings: warnings),
      isNull,
    );
    expect(warnings, isNotEmpty);
  });

  test('competing aligned stacks are not merged into an invented meter', () {
    final warnings = <String>[];
    expect(
      read([
        _digit('top1', '4', 60, 110),
        _digit('bottom1', '4', 60, 130),
        _digit('top2', '3', 100, 110),
        _digit('bottom2', '8', 100, 130),
      ], warnings: warnings),
      isNull,
    );
    expect(warnings, isNotEmpty);
  });

  test('unrelated upper and lower digits do not form a stack', () {
    expect(
      read([_digit('top', '4', 30, 110), _digit('bottom', '4', 90, 130)]),
      isNull,
    );
  });

  test('nearby duplicate boxes crossing the midpoint are not a fraction', () {
    expect(
      read([
        _digit('top', '4', 60, 119, height: 20),
        _digit('bottom', '4', 60, 121, height: 20),
      ]),
      isNull,
    );
  });

  for (final row in [110.0, 130.0]) {
    test('one detected row at y=$row does not supply the missing row', () {
      expect(read([_digit('only', '4', 60, row)]), isNull);
    });
  }
  for (final zeroOnTop in [true, false]) {
    test(
      'zero ${zeroOnTop ? 'numerator' : 'denominator'} remains unresolved',
      () {
        expect(
          read([
            _digit('top', zeroOnTop ? '0' : '4', 60, 110),
            _digit('bottom', zeroOnTop ? '4' : '0', 60, 130),
          ]),
          isNull,
        );
      },
    );
  }

  test('uses the staff slope when assigning upper and lower rows', () {
    const slope = DetectedStaff(
      id: 'sloped',
      topY: 90,
      bottomY: 150,
      lineYs: [100, 110, 120, 130, 140],
      offsetXs: [0, 200],
      offsetYs: [0, 100],
    );
    expect(
      read([
        _digit('false', '4', 30, 125, width: 24, staff: slope),
        _digit('top', '4', 60, 140, width: 24, staff: slope),
        _digit('bottom', '4', 66, 168, width: 24, staff: slope),
      ], staff: slope),
      const TimeSignature(beats: 4, beatType: 4),
    );
  });

  for (final (type, expected) in [
    ('Common', TimeSignature.common),
    ('CutCommon', TimeSignature.cut),
  ]) {
    test('retains explicit $type signs', () {
      final entry = StaffOwnedSymbol(
        staff: _staff,
        symbol: DetectedSymbol(
          id: 'sign',
          type: 'timeSig$type',
          x: 60,
          y: 105,
          width: 12,
          height: 30,
        ),
      );
      expect(read([entry]), expected);
    });
  }
}
