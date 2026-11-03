import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/project.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

/// A 4/4 staff with [beats] quarter notes per bar. A 5-beat bar holds a
/// note detected twice (its F repeated), which the checker offers to remove.
Score reviewScore([List<int> beats = const [4, 5, 4, 4, 5, 4, 4]]) =>
    NotationReviewService.ensureIdentity(
      Score(
        id: 'review',
        title: 'Study',
        composer: '',
        parts: [
          Part(
            id: 'treble',
            name: 'Upper staff',
            measures: [
              for (var m = 0; m < beats.length; m++)
                Measure(
                  number: m + 1,
                  clef: m == 0 ? const Clef(sign: 'G', line: 2) : null,
                  timeSignature: m == 0
                      ? const TimeSignature(beats: 4, beatType: 4)
                      : null,
                  symbols: [
                    for (var n = 0; n < beats[m]; n++)
                      Note(
                        step: beats[m] == 5 && n == 4
                            ? 'F'
                            : ['C', 'D', 'E', 'F', 'G', 'A', 'B'][n % 7],
                        octave: 4,
                        duration: 2,
                        type: 'quarter',
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

void main() {
  test('preview is non-mutating and cannot apply to a different revision', () {
    final score = reviewScore();
    final before = jsonEncode(score.toJson());
    final issue = NotationReviewService.issues(score).first;
    final plan = NotationReviewService.prepare(score, {
      NotationReviewService.key(score, issue),
    });
    expect(plan.entries, hasLength(1));
    expect(plan.changes, hasLength(1));
    expect(plan.changes.single.measureIndex, 1);
    expect(jsonEncode(score.toJson()), before);
    expect(plan.applyTo(score.copyWith(title: 'Changed')), isNull);
    final applied = plan.applyTo(score)!;
    expect(NotationReviewService.issues(applied), hasLength(1));
    expect(applied.reviewHistory.single.disposition, ReviewDisposition.applied);
  });

  test(
    'batch applies only selected suggestions and is one reversible edit',
    () {
      final score = reviewScore();
      final issues = NotationReviewService.issues(score);
      final one = NotationReviewService.prepare(score, {
        NotationReviewService.key(score, issues.last),
      });
      expect(one.changes.single.measureIndex, 4);
      final all = NotationReviewService.prepare(
        score,
        issues.map((i) => NotationReviewService.key(score, i)).toSet(),
      );
      expect(all.entries, hasLength(2));
      expect(all.skipped, 0);
      final edited = EditorState(
        score: score,
      ).applyEdit(score: all.applyTo(score)!);
      expect(edited.undoStack, hasLength(1));
      expect(NotationReviewService.issues(edited.score), isEmpty);
      final undone = edited.undo();
      expect(NotationReviewService.issues(undone.score), hasLength(2));
      expect(undone.score.reviewHistory, isEmpty);
      expect(undone.redo().score.reviewHistory, hasLength(2));
    },
  );

  test(
    'a dependent suggestion is omitted after the earlier fix resolves it',
    () {
      final score = reviewScore([4, 2, 6, 4]);
      final issues = NotationReviewService.issues(score);
      expect(issues, hasLength(2));
      final plan = NotationReviewService.prepare(
        score,
        issues.map((i) => NotationReviewService.key(score, i)).toSet(),
      );
      expect(plan.entries, hasLength(1));
      expect(plan.skipped, 1);
      expect(plan.changes, hasLength(2));
      expect(NotationReviewService.issues(plan.applyTo(score)!), isEmpty);
    },
  );

  test(
    'meter preview includes inherited effects across every affected staff',
    () {
      final base = reviewScore([4, 3, 3, 3, 4]);
      final score = NotationReviewService.ensureIdentity(
        base.copyWith(
          parts: [
            base.parts.first,
            Part(
              id: 'bass',
              name: 'Lower staff',
              measures: [
                for (final measure in base.parts.first.measures)
                  Measure(
                    number: measure.number,
                    clef: measure.number == 1
                        ? const Clef(sign: 'F', line: 4)
                        : null,
                    timeSignature: measure.timeSignature,
                    symbols: measure.symbols
                        .map(
                          (s) => Note.fromJson(s.toJson()..remove('reviewId')),
                        )
                        .toList(),
                  ),
              ],
            ),
          ],
        ),
      );
      final issue = NotationReviewService.issues(score).first;
      final plan = NotationReviewService.prepare(score, {
        NotationReviewService.key(score, issue),
      });
      expect(plan.scopeDescription, 'Changes 10 measures across 2 staves.');
      expect(plan.changes.map((c) => c.partIndex).toSet(), {0, 1});
    },
  );

  test(
    'kept decisions survive saving and reopen when their passage changes',
    () {
      final score = reviewScore();
      final issue = NotationReviewService.issues(score).last;
      final kept = NotationReviewService.keep(score, issue);
      final project = Project.fromJson(
        jsonDecode(
              jsonEncode(Project.create(name: 'Review', score: kept).toJson()),
            )
            as Map<String, dynamic>,
      );
      final loaded = project.decodeScore();
      expect(NotationReviewService.issues(loaded), hasLength(1));
      expect(loaded.reviewHistory.single.disposition, ReviewDisposition.kept);
      // An insertion elsewhere renumbers measures without losing the decision.
      final renumbered = loaded.insertMeasureAfterInAllParts(0);
      expect(NotationReviewService.issues(renumbered), hasLength(1));
      final changed = loaded.replaceSymbolAt(
        0,
        4,
        0,
        const Note(step: 'C', octave: 4, duration: 1, type: 'eighth'),
      );
      expect(NotationReviewService.issues(changed), hasLength(2));
    },
  );

  test(
    'history can restore an unchanged patch but never overwrites manual edits',
    () {
      final score = reviewScore();
      final issue = NotationReviewService.issues(score).first;
      final applied = NotationReviewService.prepare(score, {
        NotationReviewService.key(score, issue),
      }).applyTo(score)!;
      final entry = applied.reviewHistory.single;
      expect(NotationReviewService.canRestore(applied, entry), isTrue);
      final restored = NotationReviewService.restore(applied, entry)!;
      expect(NotationReviewService.issues(restored), hasLength(2));
      expect(restored.reviewHistory, isEmpty);
      final changed = applied.replaceSymbolAt(
        0,
        1,
        0,
        const Note(step: 'G', octave: 5, duration: 2, type: 'quarter'),
      );
      expect(NotationReviewService.canRestore(changed, entry), isFalse);
      expect(NotationReviewService.restore(changed, entry), isNull);
    },
  );

  test(
    'saved history restores a split measure without losing unrelated edits',
    () {
      final original = reviewScore([4, 8, 4]);
      final issue = NotationReviewService.issues(original).single;
      final plan = NotationReviewService.prepare(original, {
        NotationReviewService.key(original, issue),
      });
      expect(plan.passageBounds(0, proposed: false), (0, 2));
      expect(plan.passageBounds(0, proposed: true), (0, 3));
      final applied = Score.fromJson(
        jsonDecode(jsonEncode(plan.applyTo(original)!.toJson()))
            as Map<String, dynamic>,
      );
      expect(applied.parts.single.measures, hasLength(4));
      final entry = applied.reviewHistory.single;
      expect(NotationReviewService.canRestore(applied, entry), isTrue);
      final changedElsewhere = applied.replaceSymbolAt(
        0,
        3,
        0,
        const Note(step: 'G', octave: 5, duration: 2, type: 'quarter'),
      );
      final restored = NotationReviewService.restore(changedElsewhere, entry)!;
      expect(restored.parts.single.measures, hasLength(3));
      expect(restored.parts.single.measures[1].symbols, hasLength(8));
      expect((restored.getSymbolAt(0, 2, 0) as Note).pitch, 'G5');
      final changedNewBar = applied.replaceSymbolAt(
        0,
        2,
        0,
        const Note(step: 'G', octave: 5, duration: 2, type: 'quarter'),
      );
      expect(NotationReviewService.canRestore(changedNewBar, entry), isFalse);
    },
  );

  test(
    'scan evidence survives pitch/duration/meter edits, append and save',
    () {
      const source = SourceRegion(
        pageId: 'page',
        x: .1,
        y: .2,
        width: .05,
        height: .03,
      );
      final base = reviewScore();
      final note = base.getSymbolAt(0, 0, 0) as Note;
      var score = base
          .replaceSymbolAt(
            0,
            0,
            0,
            Note(
              step: note.step,
              octave: note.octave,
              duration: note.duration,
              type: note.type,
              source: source,
              reviewId: note.reviewId,
            ),
          )
          .copyWith(
            sourcePages: const [
              ScoreSourcePage(id: 'page', imageBase64: 'evidence'),
            ],
          );
      var state = EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0);
      state = state.moveSelectedSymbolUp().setSelectedDuration(eighthDuration);
      score = state.score.setTimeSignatureAt(
        0,
        const TimeSignature(beats: 3, beatType: 4),
      );
      expect((score.getSymbolAt(0, 0, 0) as Note).source?.pageId, 'page');
      expect((score.getSymbolAt(0, 0, 0) as Note).reviewId, note.reviewId);
      final appended = score.appendScore(
        reviewScore().copyWith(
          sourcePages: const [
            ScoreSourcePage(id: 'second', imageBase64: 'second-evidence'),
          ],
        ),
      );
      final loaded = Score.fromJson(
        jsonDecode(jsonEncode(appended.toJson())) as Map<String, dynamic>,
      );
      expect(loaded.sourcePages.map((p) => p.id), ['page', 'second']);
      expect((loaded.getSymbolAt(0, 0, 0) as Note).source?.x, .1);
    },
  );
}
