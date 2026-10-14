import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/mapping/domain/internal/pitch_calculator.dart';

void main() {
  const calculator = PitchCalculator();
  const treble = Clef(sign: 'G', line: 2);

  /// Pitch name of a 10x10 notehead centred on ([x], [y]).
  String? pitchAt(DetectedStaff staff, double x, double y) {
    final pitch = calculator.calculate(
      symbol: DetectedSymbol(
        id: 'n',
        type: 'noteheadBlackInSpace',
        x: x - 5,
        y: y - 5,
        width: 10,
        height: 10,
      ),
      staff: staff,
      clef: treble,
    );
    return pitch == null ? null : '${pitch.step}${pitch.octave}';
  }

  test('reads lines and spaces on an evenly ruled staff', () {
    const staff = DetectedStaff(
      id: 's',
      topY: 90,
      bottomY: 150,
      lineYs: [100, 110, 120, 130, 140],
    );
    expect(pitchAt(staff, 50, 140), 'E4'); // bottom line
    expect(pitchAt(staff, 50, 135), 'F4');
    expect(pitchAt(staff, 50, 120), 'B4'); // middle line
    expect(pitchAt(staff, 50, 100), 'F5'); // top line
    expect(pitchAt(staff, 50, 95), 'G5'); // just above the staff
    expect(pitchAt(staff, 50, 150), 'C4'); // one ledger line below
  });

  test('reads each line of a hand-ruled staff with uneven gaps', () {
    // Gaps of 8, 16, 18 and 22 px, as on one of the group's pages. An even
    // grid through the outer lines would put the second line 8 px away.
    const staff = DetectedStaff(
      id: 's',
      topY: 84,
      bottomY: 180,
      lineYs: [100, 108, 124, 142, 164],
    );
    expect(pitchAt(staff, 50, 164), 'E4');
    expect(pitchAt(staff, 50, 142), 'G4');
    expect(pitchAt(staff, 50, 124), 'B4');
    expect(pitchAt(staff, 50, 108), 'D5');
    expect(pitchAt(staff, 50, 100), 'F5');
    expect(pitchAt(staff, 50, 153), 'F4'); // the wide bottom space
    expect(pitchAt(staff, 50, 104), 'E5'); // the narrow top space
  });

  test('reads a head against a sloped staff where it runs', () {
    // The staff climbs 40 px from x=100 to x=900.
    const staff = DetectedStaff(
      id: 's',
      topY: 90,
      bottomY: 150,
      lineYs: [100, 110, 120, 130, 140],
      offsetXs: [100, 900],
      offsetYs: [0, -40],
    );
    expect(pitchAt(staff, 100, 140), 'E4');
    expect(pitchAt(staff, 900, 100), 'E4'); // bottom line is at 100 there
    expect(pitchAt(staff, 900, 80), 'B4');
    expect(pitchAt(staff, 500, 120), 'E4'); // halfway along, bottom line at 120
  });
}
