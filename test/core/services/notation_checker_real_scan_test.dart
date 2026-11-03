// The checker's suggested fixes on scores scanned from real handwritten
// pages (fixtures written by tool/real_scan_review_eval_test.dart from the
// 15 Oct and 29 Sep test photos with model B9 v2 A). Each test pins down
// what one kind of fix may change.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/services/playback_converter.dart';

void main() {
  final files =
      Directory(
          'test/fixtures/real_scans',
        ).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final scans = {
    for (final f in files)
      f.uri.pathSegments.last: Score.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      ),
  };

  /// Every fix offered on every page, with the score it was offered on,
  /// while the fixes are accepted one by one (some, like filling a bar, are
  /// only offered once a time signature has been set).
  final offered = <({String page, Score score, NotationIssue issue})>[];
  for (final MapEntry(key: page, value: scan) in scans.entries) {
    for (final score in _acceptingAll(scan)) {
      for (final issue in NotationChecker.check(score).where((i) => i.hasFix)) {
        offered.add((page: page, score: score, issue: issue));
      }
    }
  }

  Iterable<({String page, Score score, NotationIssue issue})> labelled(
    bool Function(String label) test,
  ) => offered.where((o) => test(o.issue.fixLabel!));

  test('the fixtures cover every kind of fix the scans needed', () {
    expect(scans, hasLength(6));
    for (final prefix in [
      'Split into',
      'Remove accidental',
      'Set ',
      'Draw with a flag',
    ]) {
      expect(labelled((l) => l.startsWith(prefix)), isNotEmpty, reason: prefix);
    }
  });

  test('a fix never changes the score it was offered on', () {
    for (final o in offered) {
      final before = jsonEncode(o.score.toJson());
      final after = o.issue.fix!(o.score);
      expect(jsonEncode(o.score.toJson()), before, reason: o.issue.message);
      expect(after.parts, hasLength(o.score.parts.length));
    }
  });

  test('accepting every fix in turn comes to an end', () {
    for (final MapEntry(key: page, value: scan) in scans.entries) {
      expect(_acceptingAll(scan).length, lessThan(150), reason: page);
    }
  });

  test('bar and signature fixes keep every note and rest in order', () {
    final structural = labelled(
      (l) =>
          l.startsWith('Split into') ||
          l.startsWith('Move ') ||
          l.startsWith('Set ') ||
          l.startsWith('Use ') ||
          l.startsWith('Change to') ||
          l == 'Draw with a flag',
    ).toList();
    expect(structural, isNotEmpty);
    for (final o in structural) {
      expect(
        _symbols(o.issue.fix!(o.score)),
        _symbols(o.score),
        reason: '${o.page}: ${o.issue.fixLabel}',
      );
    }
  });

  test('removing an accidental never changes how the score sounds', () {
    final removals = labelled((l) => l == 'Remove accidental').toList();
    expect(removals, isNotEmpty);
    const converter = PlaybackConverter();
    for (final o in removals) {
      expect(
        converter.buildEvents(o.issue.fix!(o.score)).map((e) => e.midiNote),
        converter.buildEvents(o.score).map((e) => e.midiNote),
        reason: '${o.page}: ${o.issue.message}',
      );
    }
  });

  // On these scans "Fill with rests" moved 82 of 95 bars further from the
  // page and "Shorten the last note" 9 of 20, so neither is offered: a
  // short or long bar is listed for the user to check against the page.
  test('a bar with the wrong number of beats is never padded or shortened', () {
    final beatIssues = [
      for (final MapEntry(key: page, value: scan) in scans.entries)
        for (final score in _acceptingAll(scan))
          for (final issue in NotationChecker.check(score))
            if (issue.kind == NotationIssueKind.beatTotal) (page, issue),
    ];
    expect(beatIssues, isNotEmpty);
    for (final (page, issue) in beatIssues) {
      final label = issue.fixLabel ?? '';
      expect(label, isNot(contains('rest')), reason: '$page: $label');
      expect(label, isNot(startsWith('Shorten')), reason: '$page: $label');
      if (!issue.hasFix && issue.message.contains('needs')) {
        expect(issue.message, contains('A note may be missing'));
      }
    }
  });
}

/// The scores a user passes through accepting every suggested fix, top of
/// the list first, from [scan] to the score with none left. A fix that
/// changes nothing is passed over. Stops after 150 accepted fixes.
List<Score> _acceptingAll(Score scan) {
  final states = [scan];
  final unchanged = <String>{};
  while (states.length <= 150) {
    final score = states.last;
    final next = NotationChecker.check(
      score,
    ).where((i) => i.hasFix && !unchanged.contains(i.key)).firstOrNull;
    if (next == null) break;
    final after = next.fix!(score);
    if (jsonEncode(after.toJson()) == jsonEncode(score.toJson())) {
      unchanged.add(next.key);
    } else {
      states.add(after);
    }
  }
  return states;
}

/// Every note and rest of every staff in reading order, without bar lines
/// or beams: what a listener would hear and a reader would play.
List<String> _symbols(Score score) => [
  for (final part in score.parts)
    for (final measure in part.measures)
      for (final s in measure.symbols)
        if (s is Note)
          'N${s.step}${s.octave}${s.alter ?? ''} ${s.type}${'.' * s.dots}'
              '${s.isChordTone ? ' chord' : ''}'
        else if (s is Rest)
          'R ${s.type}${'.' * s.dots}',
];
