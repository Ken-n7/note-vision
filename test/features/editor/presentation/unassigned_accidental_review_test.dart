import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../core/services/unassigned_accidental_review_test.dart'
    as fixture;
import '../../../support/editor_controls_harness.dart';
import 'guided_review_test.dart' show guidedScore, openReview, tap;

Score study() {
  final score = fixture.reviewScore();
  final part = score.parts.single;
  return score.copyWith(
    sourcePages: guidedScore().sourcePages,
    parts: [
      part.copyWith(
        measures: [
          part.measures.first.copyWith(
            source: const SourceRegion(
              pageId: 'photo',
              x: .05,
              y: .1,
              width: .7,
              height: .5,
            ),
          ),
          part.measures.last,
        ],
      ),
    ],
  );
}

ReviewBarEditor editor(WidgetTester tester) =>
    tester.widget(find.byType(ReviewBarEditor));
FilledButton assignButton(WidgetTester tester, [String name = 'sharp']) =>
    tester.widget(
      find
          .ancestor(
            of: find.text('Assign $name to selected note'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          )
          .first,
    );

Future<void> focusSharp(WidgetTester tester) =>
    tap(tester, find.text('2. Assign sharp'));

void main() {
  setUpAll(() async {
    for (final name in ['NotoSans', 'NotoMusic']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small', const Size(320, 568), 1.0),
    ('large-text', const Size(390, 844), 1.8),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('unassigned mark comparison fits $name', (tester) async {
      await openReview(tester, score: study(), size: size, scale: scale);
      await focusSharp(tester);
      expect(find.text('Which note needs this sharp?'), findsOneWidget);
      expect(assignButton(tester).onPressed, isNull);
      expect(editor(tester).selectionOnly, isTrue);
      await tap(tester, find.byTooltip('Next note in bar'));
      expect(assignButton(tester).onPressed, isNotNull);
      await captureControls(tester, 'unassigned-$name');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selection keeps the mark outlined; a rest cannot receive it', (
    tester,
  ) async {
    await openReview(tester, score: study());
    await focusSharp(tester);
    final mark = editor(tester).bar.unassignedAccidentals.first;
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byTooltip('Next note in bar'));
      final photo = tester.widget<ScanComparisonView>(
        find.byType(ScanComparisonView),
      );
      expect(photo.highlight?.toJson(), mark.source?.toJson());
    }
    expect(assignButton(tester).onPressed, isNull);
    expect(find.text('Note up'), findsNothing);
  });

  testWidgets(
    'changing mark resets selection and preserves the other question',
    (tester) async {
      await openReview(tester, score: study());
      await focusSharp(tester);
      await tap(tester, find.byTooltip('Next note in bar'));
      expect(assignButton(tester).onPressed, isNotNull);
      await tap(tester, find.text('3. Assign flat'));
      expect(assignButton(tester, 'flat').onPressed, isNull);
      expect(editor(tester).selectedSymbol, isNull);
      final photo = tester.widget<ScanComparisonView>(
        find.byType(ScanComparisonView),
      );
      expect(photo.highlight?.x, .3);
    },
  );

  testWidgets(
    'assign, save/reopen and Undo preserve mark evidence and history',
    (tester) async {
      final (_, storage) = await openReview(tester, score: study());
      await focusSharp(tester);
      await tap(tester, find.byTooltip('Next note in bar'));
      await tap(tester, find.text('Assign sharp to selected note'));
      expect(
        editor(tester).score.parts.first.measures.first.notes.first.alter,
        1,
      );
      expect(
        editor(
          tester,
        ).score.parts.first.measures.first.unassignedAccidentals.single.id,
        'flat',
      );
      await tap(tester, find.text('Save & close'));
      final loaded = storage.saved.last.decodeScore();
      expect(loaded.reviewHistory.single.change, 'Assign sharp to C4');
      await tap(tester, find.byTooltip('Undo'));
      await tap(tester, find.text('Save'));
      expect(
        storage.saved.last
            .decodeScore()
            .parts
            .first
            .measures
            .first
            .unassignedAccidentals,
        hasLength(2),
      );
      expect(storage.saved.last.decodeScore().reviewHistory, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await openReview(tester, score: loaded);
      expect(
        fixture.marks(editor(tester).score).single.unassignedAccidental?.id,
        'flat',
      );
      expect(
        editor(tester).score.sourcePages.single.imageBase64,
        loaded.sourcePages.single.imageBase64,
      );
    },
  );

  testWidgets('ignore only this mark and keep its decision when saved', (
    tester,
  ) async {
    final (_, storage) = await openReview(tester, score: study());
    await focusSharp(tester);
    await tap(tester, find.text('Ignore mark'));
    expect(
      fixture.marks(editor(tester).score).single.unassignedAccidental?.id,
      'flat',
    );
    expect(editor(tester).bar.notes.every((n) => n.alter == null), isTrue);
    await tap(tester, find.text('Save & close'));
    expect(
      fixture
          .marks(storage.saved.last.decodeScore())
          .single
          .unassignedAccidental
          ?.id,
      'flat',
    );
  });

  testWidgets('playback prevents accidental assignment', (tester) async {
    final (playback, _) = await openReview(tester, score: study());
    await focusSharp(tester);
    await tap(tester, find.byTooltip('Next note in bar'));
    playback.emit(PlaybackStatus.playing);
    await tester.pumpAndSettle();
    expect(assignButton(tester).onPressed, isNull);
    expect(editor(tester).bar.unassignedAccidentals, hasLength(2));
  });

  testWidgets(
    'missing photo does not hide the mark or prevent an explicit assignment',
    (tester) async {
      await openReview(tester, score: study().copyWith(sourcePages: const []));
      await focusSharp(tester);
      expect(
        find.text('No photo is attached. Compare with your original sheet.'),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Next note in bar'));
      await tap(tester, find.text('Assign sharp to selected note'));
      expect(
        editor(tester).score.parts.first.measures.first.notes.first.alter,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing coordinates never outline the selected note as the mark',
    (tester) async {
      final score = study();
      final part = score.parts.single;
      final bar = part.measures.first;
      await openReview(
        tester,
        score: score.copyWith(
          parts: [
            part.copyWith(
              measures: [
                bar.copyWith(
                  unassignedAccidentals: [
                    bar.unassignedAccidentals.first.copyWith(source: null),
                    bar.unassignedAccidentals.last,
                  ],
                ),
                part.measures.last,
              ],
            ),
          ],
        ),
      );
      await focusSharp(tester);
      expect(
        find.textContaining('exact position is unavailable'),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Next note in bar'));
      expect(
        tester
            .widget<ScanComparisonView>(find.byType(ScanComparisonView))
            .highlight,
        isNull,
      );
      expect(assignButton(tester).onPressed, isNotNull);
    },
  );
}
