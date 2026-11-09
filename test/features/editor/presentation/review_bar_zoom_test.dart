import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../core/services/unassigned_accidental_review_test.dart'
    as fixture;
import 'guided_review_test.dart' show guidedScore, openReview, tap;
import 'review_bar_fitting_test.dart' show shortInDenseScore;
import 'review_bar_navigation_test.dart'
    show mount, wideScore, horizontal, painting, position;
import 'review_bar_vertical_test.dart' show ledgerScore, vPosition;

const resetLabel = 'Reset review zoom to 100%';
double zoomPercent(WidgetTester tester) => double.parse(
  tester
      .widget<Text>(
        find.descendant(
          of: find.byTooltip(resetLabel),
          matching: find.byType(Text),
        ),
      )
      .data!
      .replaceAll('%', ''),
);

Offset symbolHead(WidgetTester tester, int index) {
  final p =
      tester.widget<CustomPaint>(painting).painter! as ScoreNotationPainter;
  final target = ScoreNotationPainter.buildSymbolTargets(
    parts: p.parts,
    engraving: p.engraving,
    measuresPerRow: p.measuresPerRow,
    minMeasureWidth: p.minMeasureWidth,
    rowHeight: p.rowHeight,
    padding: p.padding,
    rowPrefixWidth: p.rowPrefixWidth,
    tabTunings: p.tabTunings,
    singleLineParts: p.singleLineParts,
  ).singleWhere((t) => t.symbolIndex == index);
  return tester.renderObject<RenderBox>(painting).localToGlobal(target.center);
}

void visible(WidgetTester tester, int index) {
  expect(
    tester.getRect(horizontal).inflate(.5).contains(symbolHead(tester, index)),
    isTrue,
    reason: 'Symbol $index must be inside the scaled preview',
  );
}

Future<void> press(WidgetTester tester, String tooltip) =>
    tap(tester, find.byTooltip(tooltip));

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

  testWidgets(
    'fit shows the whole dense bar and scaled taps select its notes',
    (tester) async {
      final state = await mount(tester, selected: 23);
      final before = jsonEncode(state.score.toJson());
      expect(position(tester).maxScrollExtent, greaterThan(0));
      await tap(tester, find.text('Fit bar'));
      expect(zoomPercent(tester), lessThan(100));
      expect(position(tester).maxScrollExtent, closeTo(0, .01));
      for (var i = 0; i < 24; i++) {
        visible(tester, i);
        await tester.tapAt(symbolHead(tester, i));
        await tester.pumpAndSettle();
        expect(state.selected, i);
      }
      expect(state.corrections, 0);
      expect(jsonEncode(state.score.toJson()), before);
    },
  );

  testWidgets('zoom enlarges notation while following selected note and rest', (
    tester,
  ) async {
    final state = await mount(tester, selected: 23);
    final before = tester.getRect(painting).width;
    await press(tester, 'Review zoom in');
    expect(zoomPercent(tester), 125);
    expect(tester.getRect(painting).width, closeTo(before * 1.25, .01));
    for (final i in [23, 10, 0, 18]) {
      state.select(i);
      await tester.pumpAndSettle();
      visible(tester, i);
      await tester.tapAt(symbolHead(tester, i));
      await tester.pumpAndSettle();
      expect(state.selected, i);
    }
    await press(tester, 'Review zoom out');
    expect(zoomPercent(tester), 100);
    visible(tester, 18);
  });

  testWidgets('fit includes extreme high and low notes on both axes', (
    tester,
  ) async {
    await mount(tester, score: ledgerScore(), selected: 2);
    await tap(tester, find.text('Fit bar'));
    expect(zoomPercent(tester), lessThan(100));
    expect(position(tester).maxScrollExtent, closeTo(0, .01));
    expect(vPosition(tester).maxScrollExtent, closeTo(0, .01));
    for (var i = 0; i < 4; i++) {
      visible(tester, i);
    }
  });

  testWidgets(
    'enlarged ledger selection follows both directions and remains tappable',
    (tester) async {
      final state = await mount(tester, score: ledgerScore(), selected: 0);
      await press(tester, 'Review zoom in');
      await press(tester, 'Review zoom in');
      for (final i in [0, 2, 1, 3, 0]) {
        state.select(i);
        await tester.pumpAndSettle();
        visible(tester, i);
        await tester.tapAt(symbolHead(tester, i));
        await tester.pumpAndSettle();
        expect(state.selected, i);
      }
      expect(position(tester).maxScrollExtent, greaterThan(0));
      expect(vPosition(tester).maxScrollExtent, greaterThan(0));
    },
  );

  for (final (width, scale) in [
    (200.0, 1.0),
    (280.0, 1.8),
    (390.0, 1.8),
    (740.0, 1.0),
  ]) {
    testWidgets('controls wrap and fit at width $width and text $scale', (
      tester,
    ) async {
      await mount(tester, width: width, scale: scale, selected: 23);
      await tap(tester, find.text('Fit bar'));
      for (var i = 0; i < 24; i++) {
        visible(tester, i);
      }
      for (final f in [
        find.byTooltip('Review zoom out'),
        find.byTooltip('Review zoom in'),
        find.text('Fit bar'),
      ]) {
        final rect = tester.getRect(f);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width + .5));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'fit recomputes on resize while manual zoom retains its percentage',
    (tester) async {
      final state = await mount(tester, selected: 23);
      await tap(tester, find.text('Fit bar'));
      final small = zoomPercent(tester);
      state.resize(740);
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), greaterThan(small));
      visible(tester, 0);
      visible(tester, 23);
      await press(tester, resetLabel);
      await press(tester, 'Review zoom in');
      state.resize(280);
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), 125);
      visible(tester, 23);
    },
  );

  testWidgets(
    'reset restores readable size and refollows after manual panning',
    (tester) async {
      final state = await mount(tester, selected: 23);
      await tap(tester, find.text('Fit bar'));
      await press(tester, resetLabel);
      expect(zoomPercent(tester), 100);
      visible(tester, 23);
      await tester.drag(horizontal, const Offset(180, 0));
      await tester.pumpAndSettle();
      final manual = position(tester).pixels;
      state.refresh();
      await tester.pumpAndSettle();
      expect(position(tester).pixels, manual);
      await press(tester, resetLabel);
      visible(tester, 23);
    },
  );

  testWidgets(
    'zoom resets per bar and staff but survives selection and score edits',
    (tester) async {
      final state = await mount(
        tester,
        score: shortInDenseScore(),
        selected: 0,
      );
      await press(tester, 'Review zoom in');
      state.select(3);
      state.replaceScore(state.score.copyWith(title: 'Renamed'));
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), 125);
      visible(tester, 3);
      state.moveTo(0, 1);
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), 100);
      await tap(tester, find.text('Fit bar'));
      state.moveTo(1, 0);
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), 100);
    },
  );

  testWidgets('fit recomputes when a correction increases bar density', (
    tester,
  ) async {
    final state = await mount(tester, score: shortInDenseScore(), selected: 3);
    await tap(tester, find.text('Fit bar'));
    expect(zoomPercent(tester), 100);
    state.replaceScore(wideScore());
    await tester.pumpAndSettle();
    expect(zoomPercent(tester), lessThan(100));
    visible(tester, 23);
    visible(tester, 3);
  });

  testWidgets('readonly empty previews zoom safely within limits', (
    tester,
  ) async {
    final base = ledgerScore();
    final part = base.parts.first;
    await mount(
      tester,
      score: base.copyWith(
        parts: [
          part.copyWith(measures: [part.measures.first.copyWith(symbols: [])]),
        ],
      ),
      canEdit: false,
    );
    for (var i = 0; i < 8; i++) {
      await press(tester, 'Review zoom in');
    }
    expect(zoomPercent(tester), 300);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Review zoom in',
            ),
          )
          .onPressed,
      isNull,
    );
    for (var i = 0; i < 14; i++) {
      await press(tester, 'Review zoom out');
    }
    expect(zoomPercent(tester), 25);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Review zoom out',
            ),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('Fit bar'));
    expect(zoomPercent(tester), 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual zoom survives bottom side and compact Review layouts', (
    tester,
  ) async {
    final score = fixture.reviewScore().copyWith(
      sourcePages: guidedScore().sourcePages,
    );
    await openReview(tester, score: score);
    await tap(tester, find.text('2. Assign sharp'));
    await tap(tester, find.byTooltip('Next note in bar'));
    await tap(tester, find.byTooltip('Next note in bar'));
    await press(tester, 'Review zoom in');
    for (final size in [
      const Size(844, 390),
      const Size(390, 844),
      const Size(1024, 768),
      const Size(320, 568),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), 125);
      expect(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .selectedSymbol,
        1,
      );
      visible(tester, 1);
      expect(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .score
            .toJson(),
        score.toJson(),
      );
    }
  });

  testWidgets('Fit bar remains active through compact layout reparenting', (
    tester,
  ) async {
    final base = wideScore();
    final part = base.parts.first;
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
      score: base.copyWith(
        sourcePages: guidedScore().sourcePages,
        parts: [
          part.copyWith(
            measures: [
              part.measures.first.copyWith(unassignedAccidentals: [mark]),
              part.measures.last,
            ],
          ),
        ],
      ),
    );
    await tap(tester, find.text('2. Assign sharp'));
    await tap(tester, find.text('Fit bar'));
    for (final size in [
      const Size(844, 390),
      const Size(390, 844),
      const Size(320, 568),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(zoomPercent(tester), lessThan(100));
      expect(position(tester).maxScrollExtent, closeTo(0, .01));
      visible(tester, 0);
      visible(tester, 23);
    }
  });

  testWidgets(
    'zooming review leaves source photo decisions and music unchanged',
    (tester) async {
      await openReview(
        tester,
        score: fixture.reviewScore().copyWith(
          sourcePages: guidedScore().sourcePages,
        ),
      );
      await tap(tester, find.text('2. Assign sharp'));
      final editor = find.byType(ReviewBarEditor);
      final before = jsonEncode(
        tester.widget<ReviewBarEditor>(editor).score.toJson(),
      );
      final source = tester
          .widget<ScanComparisonView>(find.byType(ScanComparisonView))
          .highlight
          ?.toJson();
      await press(tester, 'Review zoom in');
      await tap(tester, find.text('Fit bar'));
      await press(tester, resetLabel);
      await tap(tester, find.byTooltip('Next note in bar'));
      visible(tester, 0);
      expect(
        jsonEncode(tester.widget<ReviewBarEditor>(editor).score.toJson()),
        before,
      );
      expect(
        tester
            .widget<ScanComparisonView>(find.byType(ScanComparisonView))
            .highlight
            ?.toJson(),
        source,
      );
    },
  );
}
