import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../core/services/unassigned_accidental_review_test.dart'
    as fixture;
import 'guided_review_test.dart' show guidedScore, openReview, tap;

Score wideScore({List<ScoreSymbol>? symbols}) {
  final bar = Measure(
    number: 1,
    clef: const Clef(sign: 'G', line: 2),
    timeSignature: const TimeSignature(beats: 4, beatType: 4),
    keySignature: const KeySignature(fifths: -5),
    unresolvedBarlines: true,
    source: const SourceRegion(
      pageId: 'photo',
      x: 0,
      y: 0,
      width: 1,
      height: 1,
    ),
    symbols:
        symbols ??
        [
          for (var i = 0; i < 24; i++)
            if (i == 10)
              const Rest(type: 'quarter', duration: 2)
            else
              Note(
                step: ['E', 'G', 'B'][i % 3],
                octave: 4,
                type: 'quarter',
                duration: 2,
              ),
        ],
  );
  return Score(
    id: 'wide',
    title: '',
    composer: '',
    parts: [
      Part(
        id: 'treble',
        name: 'Treble',
        measures: [
          bar,
          bar.copyWith(
            number: 2,
            clef: null,
            keySignature: null,
            timeSignature: null,
          ),
        ],
      ),
      Part(
        id: 'bass',
        name: 'Bass',
        measures: [bar.copyWith(clef: const Clef(sign: 'F', line: 4))],
      ),
    ],
  );
}

class PreviewHarness extends StatefulWidget {
  const PreviewHarness({
    super.key,
    required this.score,
    this.initialSelection,
    this.width = 320,
    this.scale = 1,
    this.canEdit = true,
  });
  final Score score;
  final int? initialSelection;
  final double width, scale;
  final bool canEdit;
  @override
  State<PreviewHarness> createState() => PreviewHarnessState();
}

class PreviewHarnessState extends State<PreviewHarness> {
  late Score score = widget.score;
  late int? selected = widget.initialSelection;
  late double width = widget.width;
  int part = 0, measure = 0, corrections = 0;
  void select(int? value) => setState(() => selected = value);
  void refresh() => setState(() {});
  void resize(double value) => setState(() => width = value);
  void moveTo(int p, int m) => setState(() {
    part = p;
    measure = m;
    selected = null;
  });
  void replaceScore(Score value) => setState(() => score = value);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(widget.scale)),
              child: ReviewBarEditor(
                score: score,
                part: part,
                measure: measure,
                selectedSymbol: selected,
                onSelect: select,
                onCorrect: (_, _, _) => corrections++,
                canEdit: widget.canEdit,
                setupOpen: false,
                selectionOnly: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<PreviewHarnessState> mount(
  WidgetTester tester, {
  Score? score,
  int? selected,
  double width = 320,
  double scale = 1,
  bool canEdit = true,
}) async {
  final key = GlobalKey<PreviewHarnessState>();
  await tester.pumpWidget(
    PreviewHarness(
      key: key,
      score: score ?? wideScore(),
      initialSelection: selected,
      width: width,
      scale: scale,
      canEdit: canEdit,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Finder get horizontal => find.descendant(
  of: find.byType(ReviewBarEditor),
  matching: find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  ),
);
ScrollPosition position(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(horizontal).controller!.position;
Finder get painting => find.descendant(
  of: find.byType(ReviewBarEditor),
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is ScoreNotationPainter,
  ),
);
Offset head(WidgetTester tester, int index) {
  final painter =
      tester.widget<CustomPaint>(painting).painter! as ScoreNotationPainter;
  final target = ScoreNotationPainter.buildSymbolTargets(
    parts: painter.parts,
    engraving: painter.engraving,
    measuresPerRow: painter.measuresPerRow,
    minMeasureWidth: painter.minMeasureWidth,
    rowHeight: painter.rowHeight,
    padding: painter.padding,
    rowPrefixWidth: painter.rowPrefixWidth,
    tabTunings: painter.tabTunings,
    singleLineParts: painter.singleLineParts,
  ).singleWhere((t) => t.symbolIndex == index);
  return tester.getTopLeft(painting) + target.center;
}

void expectVisible(WidgetTester tester, int index) {
  final viewport = tester.getRect(horizontal);
  final x = head(tester, index).dx;
  expect(
    x - 16,
    greaterThanOrEqualTo(viewport.left - .5),
    reason: 'Selected symbol $index is left of the viewport',
  );
  expect(
    x + 16,
    lessThanOrEqualTo(viewport.right + .5),
    reason: 'Selected symbol $index is right of the viewport',
  );
}

Future<void> arrow(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('$label note in bar'));
  await tester.pumpAndSettle();
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

  testWidgets('Next and Previous keep every selected head visible', (
    tester,
  ) async {
    final state = await mount(tester);
    final original = jsonEncode(state.score.toJson());
    for (var i = 0; i < 24; i++) {
      await arrow(tester, 'Next');
      expect(state.selected, i);
      expectVisible(tester, i);
    }
    expect(position(tester).pixels, greaterThan(0));
    for (var i = 22; i >= 0; i--) {
      await arrow(tester, 'Previous');
      expectVisible(tester, i);
    }
    expect(jsonEncode(state.score.toJson()), original);
    expect(state.corrections, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (name, width, scale) in [
    ('small', 280.0, 1.0),
    ('phone', 390.0, 1.0),
    ('large text', 390.0, 1.8),
    ('landscape', 740.0, 1.0),
  ]) {
    testWidgets('initial selection is visible on $name', (tester) async {
      await mount(tester, selected: 23, width: width, scale: scale);
      expectVisible(tester, 23);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'manual panning survives rebuilds and selecting again reveals the target',
    (tester) async {
      final state = await mount(tester, selected: 23);
      await tester.drag(horizontal, const Offset(240, 0));
      await tester.pumpAndSettle();
      final manual = position(tester).pixels;
      state.refresh();
      await tester.pumpAndSettle();
      expect(position(tester).pixels, manual);
      state.select(0);
      await tester.pumpAndSettle();
      expectVisible(tester, 0);
    },
  );

  testWidgets('resizing reveals the selection in the new viewport', (
    tester,
  ) async {
    final state = await mount(tester, selected: 23, width: 740);
    state.resize(280);
    await tester.pumpAndSettle();
    expectVisible(tester, 23);
    state.resize(740);
    await tester.pumpAndSettle();
    expectVisible(tester, 23);
  });

  testWidgets(
    'changing bars or parts resets panning and uses inherited signatures',
    (tester) async {
      final state = await mount(tester, selected: 23);
      for (final (part, bar) in [(0, 1), (1, 0), (0, 0)]) {
        state.moveTo(part, bar);
        await tester.pumpAndSettle();
        expect(position(tester).pixels, 0);
        state.select(23);
        await tester.pumpAndSettle();
        expectVisible(tester, 23);
      }
    },
  );

  testWidgets('grace notes chords rests and voices follow rendered positions', (
    tester,
  ) async {
    final notes = wideScore().parts.first.measures.first.symbols.toList();
    notes[4] = (notes[4] as Note).copyWith(
      grace: Grace.appoggiatura,
      type: 'eighth',
    );
    notes[5] = (notes[5] as Note).copyWith(type: 'whole');
    notes[6] = (notes[6] as Note).copyWith(isChordTone: true);
    notes[23] = (notes[23] as Note).copyWith(voice: 2);
    final state = await mount(tester, score: wideScore(symbols: notes));
    for (final i in [22, 4, 6, 10, 23, 5, 0]) {
      state.select(i);
      await tester.pumpAndSettle();
      expectVisible(tester, i);
    }
  });

  testWidgets(
    'reflow after a score correction keeps the selected head visible',
    (tester) async {
      final state = await mount(tester, selected: 23);
      final part = state.score.parts.first;
      final bar = part.measures.first;
      final symbols = bar.symbols.toList();
      symbols[0] = (symbols[0] as Note).copyWith(type: 'whole');
      state.replaceScore(
        state.score.copyWith(
          parts: [
            part.copyWith(
              measures: [
                bar.copyWith(symbols: symbols),
                part.measures.last,
              ],
            ),
            state.score.parts.last,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expectVisible(tester, 23);
    },
  );

  testWidgets('rapid changes and disposal never reveal a stale selection', (
    tester,
  ) async {
    final state = await mount(tester);
    state.select(23);
    state.select(0);
    state.select(22);
    await tester.pumpAndSettle();
    expectVisible(tester, 22);
    state.select(0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only review reveals its selection without enabling edits', (
    tester,
  ) async {
    final state = await mount(tester, selected: 23, canEdit: false);
    expectVisible(tester, 23);
    final next = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Next note in bar',
      ),
    );
    expect(next.onPressed, isNull);
    expect(state.corrections, 0);
  });

  testWidgets('empty bars and cleared or invalid selections are safe', (
    tester,
  ) async {
    final state = await mount(tester, score: wideScore(symbols: []));
    expect(position(tester).pixels, 0);
    state.select(99);
    await tester.pumpAndSettle();
    state.select(null);
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visible selected note remains tappable after following', (
    tester,
  ) async {
    final state = await mount(tester, selected: 22);
    final target = head(tester, 23);
    if (tester.getRect(horizontal).contains(target)) {
      await tester.tapAt(target);
    } else {
      await arrow(tester, 'Next');
      await tester.tapAt(head(tester, 23));
    }
    await tester.pumpAndSettle();
    expect(state.selected, 23);
    expectVisible(tester, 23);
  });
  testWidgets(
    'accidental review follows selection while its photo mark stays fixed',
    (tester) async {
      final score = wideScore();
      final part = score.parts.first;
      final mark = fixture
          .reviewScore()
          .parts
          .first
          .measures
          .first
          .unassignedAccidentals
          .first;
      final scan = score.copyWith(
        sourcePages: guidedScore().sourcePages,
        parts: [
          part.copyWith(
            measures: [
              part.measures.first.copyWith(unassignedAccidentals: [mark]),
              part.measures.last,
            ],
          ),
        ],
      );
      await openReview(tester, score: scan);
      await tap(tester, find.text('2. Assign sharp'));
      final before = jsonEncode(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .score
            .toJson(),
      );
      for (var i = 0; i < 24; i++) {
        await tap(tester, find.byTooltip('Next note in bar'));
        expectVisible(tester, i);
        final photo = tester.widget<ScanComparisonView>(
          find.byType(ScanComparisonView),
        );
        expect(photo.highlight?.toJson(), mark.source?.toJson());
      }
      final editor = tester.widget<ReviewBarEditor>(
        find.byType(ReviewBarEditor),
      );
      expect(editor.selectedSymbol, 23);
      expect(jsonEncode(editor.score.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('bottom and side review layouts retain the selected note', (
    tester,
  ) async {
    final score = fixture.reviewScore().copyWith(
      sourcePages: guidedScore().sourcePages,
    );
    await openReview(tester, score: score);
    await tap(tester, find.text('2. Assign sharp'));
    await tap(tester, find.byTooltip('Next note in bar'));
    await tap(tester, find.byTooltip('Next note in bar'));
    final before = jsonEncode(
      tester
          .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
          .score
          .toJson(),
    );
    for (final size in [
      const Size(844, 390),
      const Size(390, 844),
      const Size(1024, 768),
      const Size(320, 568),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final editor = tester.widget<ReviewBarEditor>(
        find.byType(ReviewBarEditor),
      );
      expect(editor.selectedSymbol, 1);
      expectVisible(tester, 1);
      final photo = tester.widget<ScanComparisonView>(
        find.byType(ScanComparisonView),
      );
      expect(
        photo.highlight?.toJson(),
        score.parts.first.measures.first.unassignedAccidentals.first.source
            ?.toJson(),
      );
      expect(jsonEncode(editor.score.toJson()), before);
    }
    expect(tester.takeException(), isNull);
  });
}
