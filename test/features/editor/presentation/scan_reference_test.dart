import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../support/editor_controls_harness.dart';

Score _score() {
  final image = img.Image(width: 600, height: 200);
  img.fill(image, color: img.ColorRgb8(250, 248, 241));
  for (var line = 0; line < 5; line++) {
    img.drawLine(
      image,
      x1: 20,
      y1: 65 + line * 15,
      x2: 580,
      y2: 65 + line * 15,
      color: img.ColorRgb8(40, 40, 40),
    );
  }
  final encoded = base64Encode(img.encodePng(image));
  return Score(
    id: 'source-reference',
    title: 'Reference Study',
    composer: '',
    sourcePages: [
      ScoreSourcePage(id: 'first', imageBase64: encoded),
      ScoreSourcePage(id: 'second', imageBase64: encoded),
    ],
    parts: [
      Part(
        id: 'p1',
        name: 'Upper staff',
        measures: [
          for (var i = 0; i < 3; i++)
            Measure(
              number: i + 1,
              clef: i == 0 ? const Clef(sign: 'G', line: 2) : null,
              timeSignature: i == 0
                  ? const TimeSignature(beats: 4, beatType: 4)
                  : null,
              symbols: [
                Note(
                  step: ['C', 'D', 'E'][i],
                  octave: 4,
                  type: 'whole',
                  duration: 8,
                  source: i == 2
                      ? null
                      : SourceRegion(
                          pageId: i == 0 ? 'first' : 'second',
                          x: .1 + i * .5,
                          y: .3,
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
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Original scan'));
  await _settlePhoto(tester);
}

Future<void> _settlePhoto(WidgetTester tester) async {
  await tester.pump();
  // Engine image decoding needs real event-loop time, outside the fake clock.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

ScanComparisonView _reference(WidgetTester tester) =>
    tester.widget(find.byType(ScanComparisonView));

void main() {
  setUpAll(loadControlsFonts);

  for (final (name, size, scale) in [
    ('phone', const Size(390, 844), 1.0),
    ('small-phone', const Size(320, 568), 1.0),
    ('large-text', const Size(390, 844), 1.8),
    ('landscape', const Size(844, 390), 1.0),
    ('tablet', const Size(1024, 768), 1.0),
  ]) {
    testWidgets('scan reference leaves paper and editing reachable on $name', (
      tester,
    ) async {
      await pumpControls(
        tester,
        score: _score(),
        size: size,
        textScale: scale,
        existingProject: true,
      );
      final before = jsonEncode(shownControlsScore(tester).toJson());
      await _open(tester);
      expect(find.byType(ScanComparisonView), findsOneWidget);
      expect(
        tester.getSize(find.byType(ScanComparisonView)).height,
        greaterThan(0),
      );
      expect(
        tester
            .getRect(find.byType(ScanComparisonView))
            .intersect(
              tester.getRect(
                find.byKey(const ValueKey('scan-reference-panel')),
              ),
            )
            .height,
        greaterThanOrEqualTo(32),
      );
      expect(
        tester
            .getRect(find.byTooltip('Close original scan'))
            .overlaps(Offset.zero & size),
        isTrue,
      );
      expect(jsonEncode(shownControlsScore(tester).toJson()), before);
      expect(tester.takeException(), isNull);
      await captureControls(tester, 'scan-reference-$name');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'D4',
      );
      expect(find.byType(ScanComparisonView), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(
        (shownControlsScore(tester).getSymbolAt(0, 0, 0) as Note).pitch,
        'C4',
      );
      await tester.tap(find.byTooltip('Close original scan'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanComparisonView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reference follows pages and never shows a previous measure image',
    (tester) async {
      await pumpControls(tester, score: _score(), existingProject: true);
      await _open(tester);
      expect(_reference(tester).page.id, 'first');
      expect(_reference(tester).highlight?.x, .1);
      await tester.tap(find.byTooltip('Next symbol'));
      await _settlePhoto(tester);
      expect(_reference(tester).page.id, 'second');
      expect(_reference(tester).highlight?.x, closeTo(.6, .0001));
      expect(_reference(tester).semanticsLabel, contains('Bar 2'));
      await tester.tap(find.byTooltip('Next symbol'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanComparisonView), findsNothing);
      expect(
        find.text('No original scan is attached to this measure.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Previous symbol'));
      await _settlePhoto(tester);
      expect(_reference(tester).page.id, 'second');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full page and selected measure views keep the correction target',
    (tester) async {
      await pumpControls(tester, score: _score(), existingProject: true);
      await _open(tester);
      expect(_reference(tester).region.width, lessThan(1));
      await tester.tap(find.byTooltip('Show full scan page'));
      await tester.pumpAndSettle();
      expect(_reference(tester).region.width, 1);
      expect(_reference(tester).highlight?.x, .1);
      await tester.tap(find.byTooltip('Show selected measure'));
      await tester.pumpAndSettle();
      expect(_reference(tester).region.width, lessThan(1));
      final before = shownControlsScore(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final saved = Score.fromJson(shownControlsScore(tester).toJson());
      expect((saved.getSymbolAt(0, 0, 0) as Note).pitch, 'D4');
      expect(
        saved.sourcePages.map((p) => p.toJson()),
        before.sourcePages.map((p) => p.toJson()),
      );
      expect(
        NotationReviewService.sourceOf(saved.getSymbolAt(0, 0, 0))?.toJson(),
        NotationReviewService.sourceOf(before.getSymbolAt(0, 0, 0))?.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scores without scan evidence have no original scan action', (
    tester,
  ) async {
    await pumpControls(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Original scan'), findsNothing);
  });
}
