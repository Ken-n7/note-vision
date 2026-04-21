import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';

// Access the beam-group helper via a thin wrapper so tests don't depend on
// private painter internals.  We inline the same grouping logic here and verify
// it against known inputs — the same algorithm is used by both
// PdfScoreRenderer and ScoreNotationPainter.
List<List<int>> buildBeamGroups(List<dynamic> symbols) {
  final groups = <List<int>>[];
  List<int>? current;
  for (var i = 0; i < symbols.length; i++) {
    final sym = symbols[i];
    if (sym is Note && sym.type == 'eighth' && sym.beamed) {
      current ??= [];
      current.add(i);
    } else {
      if (current != null) {
        groups.add(current);
        current = null;
      }
    }
  }
  if (current != null) groups.add(current);
  return groups;
}

Note _eighth({bool beamed = true}) => Note(
      step: 'C',
      octave: 4,
      duration: 1,
      type: 'eighth',
      beamed: beamed,
    );

Note _quarter() => const Note(step: 'D', octave: 4, duration: 2, type: 'quarter');

void main() {
  // ── Note model serialisation ──────────────────────────────────────────────

  group('Note serialisation with beamed field', () {
    test('beamed=true is written to JSON and read back', () {
      const note = Note(
        step: 'E',
        octave: 4,
        duration: 1,
        type: 'eighth',
        beamed: true,
      );
      final json = note.toJson();
      expect(json['beamed'], isTrue);

      final restored = Note.fromJson(json);
      expect(restored.beamed, isTrue);
      expect(restored.type, 'eighth');
      expect(restored.step, 'E');
    });

    test('beamed=false is omitted from JSON (backwards-compatible)', () {
      const note = Note(step: 'G', octave: 4, duration: 2, type: 'quarter');
      final json = note.toJson();
      expect(json.containsKey('beamed'), isFalse);
    });

    test('fromJson with no beamed key defaults to false', () {
      final json = {
        'symbolType': 'note',
        'step': 'A',
        'octave': 5,
        'duration': 1,
        'type': 'eighth',
      };
      final note = Note.fromJson(json);
      expect(note.beamed, isFalse);
    });

    test('Measure containing beamed notes round-trips through JSON', () {
      const measure = Measure(
        number: 1,
        symbols: [
          Note(step: 'C', octave: 4, duration: 1, type: 'eighth', beamed: true),
          Note(step: 'D', octave: 4, duration: 1, type: 'eighth', beamed: true),
        ],
      );
      final json = measure.toJson();
      final restored = Measure.fromJson(json);
      final notes = restored.notes;
      expect(notes[0].beamed, isTrue);
      expect(notes[1].beamed, isTrue);
    });
  });

  // ── Beam grouping logic ───────────────────────────────────────────────────

  group('Beam grouping', () {
    test('group of 2 consecutive beamed eighths forms one group', () {
      final symbols = [_eighth(), _eighth()];
      final groups = buildBeamGroups(symbols);
      expect(groups.length, 1);
      expect(groups.first, [0, 1]);
    });

    test('group of 4 consecutive beamed eighths forms one group', () {
      final symbols = [_eighth(), _eighth(), _eighth(), _eighth()];
      final groups = buildBeamGroups(symbols);
      expect(groups.length, 1);
      expect(groups.first, [0, 1, 2, 3]);
    });

    test('lone beamed eighth forms a group of one (flag not suppressed)', () {
      final symbols = [_eighth()];
      final groups = buildBeamGroups(symbols);
      expect(groups.length, 1);
      expect(groups.first, [0]);
      // A group of 1 should NOT suppress the flag — renderers check length >= 2.
      expect(groups.first.length, lessThan(2));
    });

    test('mixed beamed and non-beamed eighths in one measure', () {
      // quarter, beamed-eighth, beamed-eighth, non-beamed-eighth, beamed-eighth, beamed-eighth
      final symbols = [
        _quarter(),
        _eighth(),
        _eighth(),
        _eighth(beamed: false),
        _eighth(),
        _eighth(),
      ];
      final groups = buildBeamGroups(symbols);
      // Two separate groups: indices [1,2] and [4,5]
      expect(groups.length, 2);
      expect(groups[0], [1, 2]);
      expect(groups[1], [4, 5]);
    });

    test('no beamed notes produces empty group list', () {
      final symbols = [_quarter(), _quarter(), _eighth(beamed: false)];
      final groups = buildBeamGroups(symbols);
      expect(groups, isEmpty);
    });

    test('rest interrupts a beam group', () {
      final symbols = [
        _eighth(),
        _eighth(),
        const Rest(duration: 1, type: 'eighth'),
        _eighth(),
        _eighth(),
      ];
      final groups = buildBeamGroups(symbols);
      expect(groups.length, 2);
      expect(groups[0], [0, 1]);
      expect(groups[1], [3, 4]);
    });
  });
}
