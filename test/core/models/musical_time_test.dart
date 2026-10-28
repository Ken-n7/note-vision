import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/musical_time.dart';

void main() {
  test('triplets and fifths add to exact beats after JSON round trip', () {
    final third = MusicalTime.fromJson(MusicalTime(1, 3).toJson());
    expect(third + third + third, MusicalTime.one);
    final fifth = MusicalTime(1, 5);
    expect(fifth + fifth + fifth + fifth + fifth, MusicalTime.one);
    expect(MusicalTime(2, 6), third);
    expect(MusicalTime(-2, -6), third);
    expect(MusicalTime(0, 8), MusicalTime.zero);
  });

  test('decimal divisions do not introduce a floating point rounding grid', () {
    expect(
      MusicalTime.decimal('0.5') / MusicalTime.decimal('1.5'),
      MusicalTime(1, 3),
    );
    expect(MusicalTime.decimal('-.25'), MusicalTime(-1, 4));
    expect(MusicalTime.decimal('+12.'), MusicalTime(12));
    expect(MusicalTime(2, 3) - MusicalTime(1, 6), MusicalTime(1, 2));
  });

  test('large intermediate products neither overflow nor misorder times', () {
    final a = MusicalTime(123456789012345, 1000000000);
    expect(a + a, MusicalTime(24691357802469, 100000000));
    expect(a.compareTo(MusicalTime(123456)), greaterThan(0));
    expect(a / a, MusicalTime.one);
  });

  test('invalid denominators and excessive precision fail explicitly', () {
    expect(() => MusicalTime(1, 0), throwsArgumentError);
    expect(() => MusicalTime.one / MusicalTime.zero, throwsArgumentError);
    for (final value in ['NaN', '1e3', '', '0.0000000001']) {
      expect(() => MusicalTime.decimal(value), throwsFormatException);
    }
    expect(
      () => MusicalTime(9007199254740991) + MusicalTime.one,
      throwsFormatException,
    );
  });
}
