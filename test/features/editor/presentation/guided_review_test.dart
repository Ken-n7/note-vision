import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../support/editor_controls_harness.dart';

Score guidedScore() => Score(
  id: 'guided-scan',
  title: 'Review study',
  composer: '',
  sourcePages: [
    ScoreSourcePage(
      id: 'photo',
      imageBase64: base64Encode(
        img.encodePng(img.Image(width: 600, height: 300)),
      ),
    ),
  ],
  parts: [
    for (var p = 0; p < 2; p++)
      Part(
        id: 'p$p',
        name: 'Row ${p + 1}',
        measures: [
          for (var m = 0; m < 2; m++)
            Measure(
              number: m + 1,
              clef: m == 0 ? const Clef(sign: 'G', line: 2) : null,
              timeSignature: m == 0
                  ? TimeSignature(beats: p == 0 ? 2 : 3, beatType: 4)
                  : null,
              symbols: [
                for (var n = 0; n < 3; n++)
                  Note(
                    step: ['C', 'E', 'G'][n],
                    octave: 4,
                    type: 'quarter',
                    duration: 2,
                    confidence: n == 0 ? .4 : .95,
                    source: SourceRegion(
                      pageId: 'photo',
                      x: .1 + n * .15,
                      y: .2 + p * .4,
                      width: .05,
                      height: .2,
                    ),
                  ),
              ],
            ),
        ],
      ),
  ],
);

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pumpAndSettle();
}

Future<(ControlsPlayback, ControlsStorage)> openReview(
  WidgetTester tester, {
  Score? score,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  final services = await pumpControls(
    tester,
    score: score ?? guidedScore(),
    size: size,
    textScale: scale,
    existingProject: true,
  );
  await tester.tap(find.byTooltip('Review & Correct'));
  await tester.pump();
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  return services;
}

void main() {
  setUpAll(loadControlsFonts);

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone', const Size(320, 568), 1.0),
    ('large-text', const Size(390, 844), 1.8),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('guided photo comparison fits $name', (tester) async {
      await openReview(tester, size: size, scale: scale);
      expect(find.byType(ScanComparisonView), findsOneWidget);
      expect(find.text('4 bars to check · 0 for later'), findsOneWidget);
      expect(find.text('Batch'), findsNothing);
      expect(find.text('History'), findsNothing);
      await captureControls(tester, 'guided-review-$name');
      await tap(tester, find.text('Setup matches photo'));
      expect(find.text('Check this symbol'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'note correction stays in review, preserves evidence and undoes',
    (tester) async {
      final (_, storage) = await openReview(
        tester,
        size: const Size(1024, 768),
      );
      final before = tester
          .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
          .score;
      await tap(tester, find.byTooltip('Next note in bar'));
      await tap(tester, find.text('Note up'));
      await tap(tester, find.text('Save & close'));
      final changed = storage.saved.last.decodeScore();
      expect((changed.getSymbolAt(0, 0, 0) as Note).step, 'D');
      expect(changed.parts[1].toJson(), before.parts[1].toJson());
      expect(
        changed.sourcePages.single.imageBase64,
        guidedScore().sourcePages.single.imageBase64,
      );
      expect((changed.getSymbolAt(0, 0, 0) as Note).source!.x, .1);
      await tap(tester, find.byTooltip('Undo'));
      await tap(tester, find.text('Save'));
      expect(
        (storage.saved.last.decodeScore().getSymbolAt(0, 0, 0) as Note).step,
        'C',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'meter correction affects this row and can be restored from history',
    (tester) async {
      final (_, storage) = await openReview(
        tester,
        size: const Size(1024, 768),
      );
      final dropdown = find.byType(DropdownButtonFormField<TimeSignature>);
      await tap(tester, dropdown);
      await tap(tester, find.text('4/4').last);
      await tap(tester, find.text('Save & close'));
      final corrected = storage.saved.last.decodeScore();
      expect(corrected.parts[0].measures[0].timeSignature!.beats, 4);
      expect(corrected.parts[1].measures[0].timeSignature!.beats, 3);
      final entry = corrected.reviewHistory.lastWhere(
        (e) => e.disposition == ReviewDisposition.applied,
      );
      final restored = NotationReviewService.restore(corrected, entry)!;
      expect(restored.parts[0].measures[0].timeSignature!.beats, 2);
      expect(restored.parts[1].measures[0].timeSignature!.beats, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('key correction preserves other rows and can be undone', (
    tester,
  ) async {
    final (_, storage) = await openReview(tester, size: const Size(1024, 768));
    final before = tester
        .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
        .score;
    await tap(tester, find.byType(DropdownButtonFormField<int>));
    await tap(tester, find.text('3 sharps ♯').last);
    await tap(tester, find.text('Save & close'));
    final after = storage.saved.last.decodeScore();
    expect(after.parts[0].measures[0].keySignature!.fifths, 3);
    expect(after.parts[1].toJson(), before.parts[1].toJson());
    await tap(tester, find.byTooltip('Undo'));
    await tap(tester, find.text('Save'));
    expect(
      storage.saved.last.decodeScore().parts[0].measures[0].keySignature,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('illustrated note lengths edit the selected note only', (
    tester,
  ) async {
    final (_, storage) = await openReview(tester, size: const Size(1024, 768));
    await tap(tester, find.byTooltip('Next note in bar'));
    final before = tester
        .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
        .score;
    expect(
      tester
          .widget<ScanComparisonView>(find.byType(ScanComparisonView))
          .highlight!
          .x,
      .1,
    );
    await tap(tester, find.byTooltip('Half note length'));
    await tap(tester, find.text('Save & close'));
    final after = storage.saved.last.decodeScore();
    expect((after.getSymbolAt(0, 0, 0) as Note).type, 'half');
    expect(
      after.getSymbolAt(0, 0, 1)!.toJson(),
      before.getSymbolAt(0, 0, 1)!.toJson(),
    );
    expect(
      (after.getSymbolAt(0, 0, 0) as Note).source!.toJson(),
      (before.getSymbolAt(0, 0, 0) as Note).source!.toJson(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('defer and save keeps questions pending after reopening', (
    tester,
  ) async {
    final (_, storage) = await openReview(tester);
    await tap(tester, find.text('Not sure · Review later'));
    expect(find.text('3 bars to check · 1 for later'), findsOneWidget);
    await tap(tester, find.text('Save & close'));
    final saved = storage.saved.last.decodeScore();
    expect(
      saved.reviewHistory.every(
        (e) => e.disposition == ReviewDisposition.deferred,
      ),
      isTrue,
    );
    final pending = NotationReviewService.issues(saved);
    expect(
      pending.where((i) => i.measureIndex == 0 && i.partIndex == 0),
      isNotEmpty,
    );
    await openReview(tester, score: saved);
    expect(find.text('3 bars to check · 1 for later'), findsOneWidget);
    final editor = tester.widget<ReviewBarEditor>(find.byType(ReviewBarEditor));
    expect(editor.measure, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deferring every bar does not claim the score is correct', (
    tester,
  ) async {
    await openReview(tester);
    for (var i = 0; i < 4; i++) {
      await tap(tester, find.text('Not sure · Review later'));
    }
    expect(find.text('Saved for later'), findsOneWidget);
    expect(find.text('Review complete'), findsNothing);
    expect(find.textContaining('checker can miss'), findsOneWidget);
    await tap(tester, find.text('Review saved bars'));
    await tap(tester, find.text('Resume this bar'));
    expect(find.text('1 bar to check · 3 for later'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listen uses only this bar and locks corrections until stopped', (
    tester,
  ) async {
    final (playback, _) = await openReview(tester);
    await tap(tester, find.byTooltip('Next bar to review'));
    await tap(tester, find.text('Listen to this bar'));
    expect(playback.soughtPart, 0);
    expect(playback.soughtMeasure, 1);
    expect(playback.soughtThroughMeasure, 1);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Setup matches photo'),
    );
    expect(button.onPressed, isNull);
    await tap(tester, find.text('Stop listening'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Setup matches photo'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
