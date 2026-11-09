import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../core/services/unassigned_accidental_review_test.dart'
    as fixture;
import 'guided_review_test.dart' show guidedScore, openReview, tap;
import 'review_bar_navigation_test.dart'
    show wideScore, mount, horizontal, position, painting, head, expectVisible;

Score shortInDenseScore() {
  final score = wideScore();
  final part = score.parts.first;
  final bar = part.measures.first;
  return score.copyWith(
    parts: [
      part.copyWith(
        measures: [
          bar.copyWith(symbols: bar.symbols.take(4).toList()),
          part.measures.last,
        ],
      ),
      score.parts.last,
    ],
  );
}

ScoreNotationPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(painting).painter! as ScoreNotationPainter;
void allHeadsFit(WidgetTester tester) {
  final count = painter(tester).parts.single.single.symbols.length;
  expect(position(tester).maxScrollExtent, closeTo(0, .01));
  for (var i = 0; i < count; i++) {
    expectVisible(tester, i);
  }
}

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

  testWidgets('a short bar fits beside unrelated dense bars and staves', (
    tester,
  ) async {
    final state = await mount(tester, score: shortInDenseScore());
    final before = jsonEncode(state.score.toJson());
    allHeadsFit(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(head(tester, i));
      await tester.pumpAndSettle();
      expect(state.selected, i);
    }
    expect(jsonEncode(state.score.toJson()), before);
    expect(state.corrections, 0);
  });

  for (final (name, width, scale) in [
    ('small', 280.0, 1.0),
    ('phone', 390.0, 1.0),
    ('large text', 390.0, 1.8),
    ('landscape', 740.0, 1.0),
  ]) {
    testWidgets(
      'short bar fills the $name viewport without horizontal panning',
      (tester) async {
        await mount(
          tester,
          score: shortInDenseScore(),
          width: width,
          scale: scale,
        );
        allHeadsFit(tester);
        expect(
          tester.getSize(painting).width,
          closeTo(tester.getSize(horizontal).width, .01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unrelated score density cannot change the current bar spacing', (
    tester,
  ) async {
    final state = await mount(tester, score: shortInDenseScore());
    final original = [for (var i = 0; i < 4; i++) head(tester, i)];
    final part = state.score.parts.first;
    final dense = part.measures.last;
    state.replaceScore(
      state.score.copyWith(
        parts: [
          part.copyWith(
            measures: [
              part.measures.first,
              dense.copyWith(
                symbols: [...dense.symbols, ...dense.symbols, ...dense.symbols],
              ),
            ],
          ),
          state.score.parts.last,
        ],
      ),
    );
    await tester.pumpAndSettle();
    allHeadsFit(tester);
    expect([for (var i = 0; i < 4; i++) head(tester, i)], original);
  });

  testWidgets(
    'dense bars retain readable spacing scrolling and selection following',
    (tester) async {
      final state = await mount(tester, selected: 23);
      expect(position(tester).maxScrollExtent, greaterThan(0));
      final p = painter(tester);
      expect(
        p.minMeasureWidth,
        greaterThanOrEqualTo(p.engraving!.minimumBarWidth),
      );
      for (var i = 1; i < 24; i++) {
        expect(
          head(tester, i).dx - head(tester, i - 1).dx,
          greaterThanOrEqualTo(15),
        );
      }
      expectVisible(tester, 23);
      state.select(0);
      await tester.pumpAndSettle();
      expectVisible(tester, 0);
    },
  );

  testWidgets(
    'resizing switches between fitting and scrolling without losing selection',
    (tester) async {
      final state = await mount(
        tester,
        score: shortInDenseScore(),
        width: 200,
        selected: 3,
      );
      expect(position(tester).maxScrollExtent, greaterThan(0));
      expectVisible(tester, 3);
      state.resize(390);
      await tester.pumpAndSettle();
      allHeadsFit(tester);
      expect(state.selected, 3);
      state.resize(200);
      await tester.pumpAndSettle();
      expect(position(tester).maxScrollExtent, greaterThan(0));
      expectVisible(tester, 3);
    },
  );

  testWidgets(
    'each bar gets its own width when navigating between short and dense',
    (tester) async {
      final state = await mount(tester, score: shortInDenseScore());
      allHeadsFit(tester);
      state.moveTo(0, 1);
      await tester.pumpAndSettle();
      expect(position(tester).maxScrollExtent, greaterThan(0));
      state.select(23);
      await tester.pumpAndSettle();
      expectVisible(tester, 23);
      state.moveTo(0, 0);
      await tester.pumpAndSettle();
      allHeadsFit(tester);
      expect(position(tester).pixels, 0);
    },
  );

  testWidgets('inherited clef key and meter remain intact in a fitted bar', (
    tester,
  ) async {
    final score = shortInDenseScore();
    final part = score.parts.first;
    final first = part.measures.first.copyWith(
      clef: const Clef(sign: 'F', line: 4),
      keySignature: const KeySignature(fifths: 7),
      timeSignature: const TimeSignature(beats: 6, beatType: 8),
    );
    final next = first.copyWith(
      number: 2,
      clef: null,
      keySignature: null,
      timeSignature: null,
    );
    final state = await mount(
      tester,
      score: score.copyWith(
        parts: [
          part.copyWith(measures: [first, next]),
        ],
      ),
    );
    state.moveTo(0, 1);
    await tester.pumpAndSettle();
    allHeadsFit(tester);
    final bar = painter(tester).parts.single.single;
    expect(bar.clef, first.clef);
    expect(bar.keySignature, first.keySignature);
    expect(bar.timeSignature, first.timeSignature);
  });

  testWidgets('current bar corrections recalculate its minimum width', (
    tester,
  ) async {
    final state = await mount(tester, score: shortInDenseScore());
    allHeadsFit(tester);
    final original = state.score;
    final part = original.parts.first;
    final bar = part.measures.first;
    state.replaceScore(
      original.copyWith(
        parts: [
          part.copyWith(
            measures: [
              bar.copyWith(
                symbols: wideScore().parts.first.measures.first.symbols,
              ),
              part.measures.last,
            ],
          ),
          original.parts.last,
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(position(tester).maxScrollExtent, greaterThan(0));
    state.replaceScore(original);
    await tester.pumpAndSettle();
    allHeadsFit(tester);
  });

  testWidgets('empty and single-note bars fit without inventing symbols', (
    tester,
  ) async {
    for (final symbols in [
      <Note>[],
      [const Note(step: 'E', octave: 4, type: 'whole', duration: 8)],
    ]) {
      final state = await mount(tester, score: wideScore(symbols: symbols));
      allHeadsFit(tester);
      expect(state.score.parts.first.measures.first.symbols, symbols);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fitted accidental review keeps its photo and decision evidence unchanged',
    (tester) async {
      final score = shortInDenseScore();
      final part = score.parts.first;
      final mark = fixture
          .reviewScore()
          .parts
          .first
          .measures
          .first
          .unassignedAccidentals
          .first;
      await openReview(
        tester,
        score: score.copyWith(
          sourcePages: guidedScore().sourcePages,
          parts: [
            part.copyWith(
              measures: [
                part.measures.first.copyWith(unassignedAccidentals: [mark]),
                part.measures.last,
              ],
            ),
            score.parts.last,
          ],
        ),
      );
      await tap(tester, find.text('2. Assign sharp'));
      final before = jsonEncode(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .score
            .toJson(),
      );
      allHeadsFit(tester);
      for (var i = 0; i < 4; i++) {
        await tap(tester, find.byTooltip('Next note in bar'));
        allHeadsFit(tester);
        expect(
          tester
              .widget<ScanComparisonView>(find.byType(ScanComparisonView))
              .highlight
              ?.toJson(),
          mark.source?.toJson(),
        );
      }
      expect(
        jsonEncode(
          tester
              .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
              .score
              .toJson(),
        ),
        before,
      );
    },
  );
}
