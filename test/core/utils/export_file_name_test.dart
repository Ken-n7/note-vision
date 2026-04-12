import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/utils/export_file_name.dart';

void main() {
  group('safeExportFileName', () {
    test('returns title with spaces replaced by underscores', () {
      expect(safeExportFileName('Ode to Joy'), 'Ode_to_Joy');
    });

    test('returns score for empty title', () {
      expect(safeExportFileName(''), 'score');
    });

    test('returns score for whitespace-only title', () {
      expect(safeExportFileName('   '), 'score');
    });

    test('replaces special characters with underscores', () {
      // colon, dot, space, parentheses are all replaced; digits and letters kept
      expect(safeExportFileName('Piano: No. 1 (draft)'), 'Piano__No__1__draft_');
    });

    test('preserves hyphens', () {
      expect(safeExportFileName('Well-Tempered Clavier'), 'Well-Tempered_Clavier');
    });

    test('preserves already-safe alphanumeric title unchanged', () {
      expect(safeExportFileName('SimpleMelody'), 'SimpleMelody');
    });

    test('preserves underscores in title', () {
      expect(safeExportFileName('my_score'), 'my_score');
    });

    test('trims leading and trailing whitespace before converting', () {
      expect(safeExportFileName('  Minuet  '), 'Minuet');
    });

    test('handles single character title', () {
      expect(safeExportFileName('A'), 'A');
    });

    test('handles title that is only special characters', () {
      expect(safeExportFileName('!!!'), '___');
    });
  });
}
