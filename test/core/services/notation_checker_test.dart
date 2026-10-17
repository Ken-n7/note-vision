import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_checker.dart';

Note q(String step, {int? alter, double? confidence}) => Note(
  step: step,
  octave: 4,
  alter: alter,
  duration: 2,
  type: 'quarter',
  confidence: confidence,
);

Note half(String step) =>
    Note(step: step, octave: 4, duration: 4, type: 'half');

Note eighth(String step, {bool beamed = false}) =>
    Note(step: step, octave: 4, duration: 1, type: 'eighth', beamed: beamed);

const r = Rest(duration: 2, type: 'quarter');

/// A one-staff score in [meter] (none when null), treble clef, key [fifths].
Score score(
  List<List<ScoreSymbol>> bars, {
  TimeSignature? meter = const TimeSignature(beats: 4, beatType: 4),
  int fifths = 0,
  bool clef = true,
}) => Score(
  id: 's',
  title: 't',
  composer: '',
  parts: [
    Part(
      id: 'P1',
      name: 'Treble',
      measures: [
        for (var i = 0; i < bars.length; i++)
          Measure(
            number: i + 1,
            clef: i == 0 && clef ? const Clef(sign: 'G', line: 2) : null,
            timeSignature: i == 0 ? meter : null,
            keySignature: i == 0 ? KeySignature(fifths: fifths) : null,
            symbols: bars[i],
          ),
      ],
    ),
  ],
);

List<ScoreSymbol> full() => [q('C'), q('D'), q('E'), q('F')];

void main() {
  test('a correct score has no issues', () {
    final s = score([
      full(),
      full(),
      [half('G'), r, q('A')],
      full(),
    ]);
    expect(NotationChecker.check(s), isEmpty);
  });

  test('a short bar can be filled with rests', () {
    final s = score([
      full(),
      [q('C'), q('D')],
      full(),
    ]);
    final issues = NotationChecker.check(s);
    expect(issues, hasLength(1));
    expect(issues.single.kind, NotationIssueKind.beatTotal);
    expect(issues.single.measureIndex, 1);
    expect(issues.single.fixLabel, 'Fill with rests');
    expect(NotationChecker.check(issues.single.fix!(s)), isEmpty);
  });

  test('a short first bar is a pickup, not an issue', () {
    final s = score([
      [q('G')],
      full(),
      full(),
    ]);
    expect(NotationChecker.check(s), isEmpty);
  });

  test('a note detected twice is offered for removal', () {
    final s = score([
      full(),
      [q('C'), q('D'), q('D'), q('E'), q('F')],
      full(),
    ]);
    final issue = NotationChecker.check(s).single;
    expect(issue.fixLabel, startsWith('Remove the repeated'));
    final fixed = issue.fix!(s);
    expect(fixed.parts.first.measures[1].symbols, hasLength(4));
    expect(NotationChecker.check(fixed), isEmpty);
  });

  test('two bars merged by a missed barline are split again', () {
    final s = score([
      full(),
      [...full(), ...full()],
      full(),
      [],
    ]);
    final issue = NotationChecker.check(s).single;
    expect(issue.fixLabel, 'Split into 2 bars');
    final fixed = issue.fix!(s);
    // The trailing empty bar is taken over, so the length stays the same.
    expect(fixed.parts.first.measures, hasLength(4));
    expect(NotationChecker.check(fixed), isEmpty);
  });

  test('a barline read one note early moves the note back', () {
    final s = score([
      full(),
      [q('C'), q('D'), q('E')],
      [q('F'), ...full()],
      full(),
    ]);
    final issues = NotationChecker.check(s);
    expect(issues, hasLength(2));
    final fixed = issues.first.fix!(s);
    expect(NotationChecker.check(fixed), isEmpty);
    expect((fixed.parts.first.measures[1].symbols.last as Note).step, 'F');
  });

  test(
    'bars that follow another meter suggest changing the time signature',
    () {
      final threeFour = [q('C'), q('D'), q('E')];
      final s = score([threeFour, threeFour, threeFour, threeFour, threeFour]);
      final issues = NotationChecker.check(s);
      expect(issues, hasLength(1), reason: 'bars are not reported one by one');
      expect(issues.single.kind, NotationIssueKind.timeSignature);
      expect(issues.single.fixLabel, 'Change to 3/4');
      expect(NotationChecker.check(issues.single.fix!(s)), isEmpty);
    },
  );

  test('a score with no time signature gets one from its bars', () {
    final s = score([full(), full(), full()], meter: null);
    final issue = NotationChecker.check(s).single;
    expect(issue.fixLabel, 'Set 4/4');
    expect(NotationChecker.check(issue.fix!(s)), isEmpty);
  });

  test(
    'an accidental the key already has is flagged; a courtesy one is not',
    () {
      // G major: F is sharp.
      final redundant = score([
        full(),
        [q('F', alter: 1), q('G'), q('A'), q('B')],
      ], fifths: 1);
      final issue = NotationChecker.check(redundant).single;
      expect(issue.kind, NotationIssueKind.misplacedAccidental);
      final fixed = issue.fix!(redundant);
      expect(
        (fixed.parts.first.measures[1].symbols.first as Note).alter,
        isNull,
      );

      final courtesy = score([
        [q('F', alter: 0), q('G'), q('A'), q('B')],
        [q('F', alter: 1), q('G'), q('A'), q('B')],
      ], fifths: 1);
      expect(NotationChecker.check(courtesy), isEmpty);
    },
  );

  test('a lone beamed note is flagged and can take a flag', () {
    final s = score([
      full(),
      [eighth('C', beamed: true), eighth('D'), q('E'), half('F')],
    ]);
    final issue = NotationChecker.check(s).single;
    expect(issue.kind, NotationIssueKind.missingComponent);
    expect(issue.symbolIndex, 0);
    expect(NotationChecker.check(issue.fix!(s)), isEmpty);
  });

  test('a staff without a clef is flagged', () {
    final s = score([full(), full()], clef: false);
    final issue = NotationChecker.check(s).single;
    expect(issue.kind, NotationIssueKind.missingComponent);
    expect(NotationChecker.check(issue.fix!(s)), isEmpty);
  });

  test('low-confidence detections are flagged for review without a fix', () {
    final s = score([
      full(),
      [q('C', confidence: 0.45), q('D', confidence: 0.92), q('E'), q('F')],
    ]);
    final issue = NotationChecker.check(s).single;
    expect(issue.kind, NotationIssueKind.lowConfidence);
    expect(issue.symbolIndex, 0);
    expect(issue.hasFix, isFalse);
  });

  test('confidence survives a save and load', () {
    final note = q('C', confidence: 0.5);
    expect(Note.fromJson(note.toJson()).confidence, 0.5);
    const rest = Rest(duration: 2, type: 'quarter', confidence: 0.4);
    expect(Rest.fromJson(rest.toJson()).confidence, 0.4);
  });
}
