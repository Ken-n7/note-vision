import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/review_bar_editor.dart';
import 'package:note_vision/features/editor/presentation/widgets/scan_comparison_view.dart';

import '../../../core/services/unassigned_accidental_review_test.dart'
    as fixture;
import 'guided_review_test.dart' show guidedScore, openReview, tap;
import 'review_bar_navigation_test.dart'
    show mount, wideScore, horizontal, painting, head, expectVisible;

Score ledgerScore({Clef clef = const Clef(sign: 'G', line: 2)}) => Score(
  id: 'ledger-preview',
  title: 'Ledger review',
  composer: '',
  parts: [
    Part(
      id: 'P1',
      name: 'Staff',
      measures: [
        Measure(
          number: 1,
          clef: clef,
          timeSignature: const TimeSignature(beats: 4, beatType: 4),
          symbols: const [
            Note(step: 'C', octave: 1, type: 'quarter', duration: 2, alter: 0),
            Note(step: 'E', octave: 4, type: 'quarter', duration: 2),
            Note(step: 'C', octave: 8, type: 'quarter', duration: 2),
            Note(step: 'G', octave: 4, type: 'quarter', duration: 2),
          ],
        ),
      ],
    ),
  ],
);
Finder get vertical => find.descendant(
  of: find.byType(ReviewBarEditor),
  matching: find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.vertical,
  ),
);
ScrollPosition vPosition(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(vertical).controller!.position;
void expectInPreview(WidgetTester tester, int index) {
  expectVisible(tester, index);
  final box = tester.getRect(horizontal);
  final y = head(tester, index).dy;
  expect(
    y - 16,
    greaterThanOrEqualTo(box.top - .5),
    reason: 'Head $index above the preview',
  );
  expect(
    y + 16,
    lessThanOrEqualTo(box.bottom + .5),
    reason: 'Head $index below the preview',
  );
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

  testWidgets('high and low selected heads stay inside the preview', (
    tester,
  ) async {
    final state = await mount(tester, score: ledgerScore(), selected: 0);
    final before = jsonEncode(state.score.toJson());
    expectInPreview(tester, 0);
    expect(vPosition(tester).pixels, greaterThan(0));
    expect(tester.getSize(horizontal).height, lessThanOrEqualTo(240));
    for (final index in [2, 1, 0, 3, 2]) {
      state.select(index);
      await tester.pumpAndSettle();
      expectInPreview(tester, index);
    }
    expect(jsonEncode(state.score.toJson()), before);
    expect(state.corrections, 0);
  });

  for (final clef in [
    const Clef(sign: 'G', line: 2),
    const Clef(sign: 'F', line: 4),
    const Clef(sign: 'C', line: 3),
    const Clef(sign: 'G', line: 2, octave: -1),
  ]) {
    testWidgets(
      'vertical following uses ${clef.sign} line ${clef.line} octave ${clef.octave}',
      (tester) async {
        final state = await mount(tester, score: ledgerScore(clef: clef));
        for (final index in [0, 2, 3, 1]) {
          state.select(index);
          await tester.pumpAndSettle();
          expectInPreview(tester, index);
        }
      },
    );
  }

  testWidgets('initial unselected preview reveals its first low note', (
    tester,
  ) async {
    final state = await mount(tester, score: ledgerScore());
    expect(state.selected, isNull);
    expectInPreview(tester, 0);
  });

  testWidgets('manual vertical panning survives unrelated rebuilds', (
    tester,
  ) async {
    final state = await mount(tester, score: ledgerScore(), selected: 0);
    final before = vPosition(tester).pixels;
    await tester.drag(horizontal, const Offset(0, 100));
    await tester.pumpAndSettle();
    final manual = vPosition(tester).pixels;
    expect(manual, lessThan(before));
    state.refresh();
    await tester.pumpAndSettle();
    expect(vPosition(tester).pixels, manual);
    state.select(2);
    await tester.pumpAndSettle();
    expectInPreview(tester, 2);
  });

  testWidgets('both axes follow long bars with ledger notes', (tester) async {
    final base = wideScore();
    final part = base.parts.first;
    final bar = part.measures.first;
    final notes = bar.symbols.toList();
    notes[0] = (notes[0] as Note).copyWith(octave: 1);
    notes[23] = (notes[23] as Note).copyWith(octave: 8);
    final state = await mount(
      tester,
      score: base.copyWith(
        parts: [
          part.copyWith(
            measures: [
              bar.copyWith(symbols: notes),
              part.measures.last,
            ],
          ),
        ],
      ),
      selected: 0,
      width: 280,
    );
    for (final i in [23, 10, 0, 22, 23]) {
      state.select(i);
      await tester.pumpAndSettle();
      expectInPreview(tester, i);
    }
    state.resize(740);
    await tester.pumpAndSettle();
    expectInPreview(tester, 23);
  });

  testWidgets('pitch and layout edits recompute vertical following', (
    tester,
  ) async {
    final state = await mount(tester, score: ledgerScore(), selected: 1);
    final part = state.score.parts.first;
    final bar = part.measures.first;
    final notes = bar.symbols.toList();
    notes[1] = (notes[1] as Note).copyWith(octave: 0);
    state.replaceScore(
      state.score.copyWith(
        parts: [
          part.copyWith(measures: [bar.copyWith(symbols: notes)]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expectInPreview(tester, 1);
  });

  testWidgets(
    'lyrics and markings use the same headroom as drawing and tapping',
    (tester) async {
      final base = ledgerScore();
      final part = base.parts.first;
      final bar = part.measures.first;
      final notes = bar.symbols.toList();
      notes[0] = (notes[0] as Note).copyWith(
        lyrics: [
          for (var i = 1; i <= 4; i++) Lyric(text: 'Verse $i', verse: '$i'),
        ],
      );
      notes[2] = (notes[2] as Note).copyWith(
        lyrics: const [Lyric(text: 'Above', above: true)],
      );
      final state = await mount(
        tester,
        score: base.copyWith(
          parts: [
            part.copyWith(
              measures: [
                bar.copyWith(
                  symbols: notes,
                  annotations: const [
                    ScoreAnnotation(
                      kind: AnnotationKind.staffText,
                      text: 'Above staff',
                    ),
                    ScoreAnnotation(
                      kind: AnnotationKind.staffText,
                      text: 'Below staff',
                      below: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        selected: 0,
      );
      for (final i in [0, 2, 1, 3]) {
        state.select(i);
        await tester.pumpAndSettle();
        expectInPreview(tester, i);
      }
      state.select(2);
      await tester.pumpAndSettle();
      await tester.tapAt(head(tester, 2));
      await tester.pumpAndSettle();
      expect(state.selected, 2);
    },
  );

  testWidgets(
    'first note remains visible when other bars reserve large headroom',
    (tester) async {
      final base = ledgerScore();
      final part = base.parts.first;
      final ledger = part.measures.first;
      final normal = ledger.copyWith(
        number: 1,
        symbols: const [Note(step: 'E', octave: 4, type: 'whole', duration: 8)],
      );
      final state = await mount(
        tester,
        score: base.copyWith(
          parts: [
            part.copyWith(measures: [normal, ledger.copyWith(number: 2)]),
          ],
        ),
      );
      expectInPreview(tester, 0);
      expect(state.selected, isNull);
      state.moveTo(0, 1);
      await tester.pumpAndSettle();
      expectInPreview(tester, 0);
    },
  );

  testWidgets('empty bars and readonly or cleared selections remain safe', (
    tester,
  ) async {
    final state = await mount(
      tester,
      score: ledgerScore(),
      selected: 2,
      canEdit: false,
    );
    expectInPreview(tester, 2);
    state.select(null);
    await tester.pumpAndSettle();
    final part = state.score.parts.first;
    state.replaceScore(
      state.score.copyWith(
        parts: [
          part.copyWith(measures: [part.measures.first.copyWith(symbols: [])]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(painterSymbols(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ledger-note accidental review retains selection and photo through rotation',
    (tester) async {
      final base = ledgerScore();
      final part = base.parts.first;
      final bar = part.measures.first;
      final mark = fixture
          .reviewScore()
          .parts
          .first
          .measures
          .first
          .unassignedAccidentals
          .first;
      final score = base.copyWith(
        sourcePages: guidedScore().sourcePages,
        parts: [
          part.copyWith(
            measures: [
              bar.copyWith(
                source: const SourceRegion(
                  pageId: 'photo',
                  x: 0,
                  y: 0,
                  width: 1,
                  height: 1,
                ),
                unassignedAccidentals: [mark],
              ),
            ],
          ),
        ],
      );
      await openReview(tester, score: score);
      await tap(tester, find.text('2. Assign sharp'));
      final before = jsonEncode(
        tester
            .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
            .score
            .toJson(),
      );
      for (var i = 0; i < 3; i++) {
        await tap(tester, find.byTooltip('Next note in bar'));
        expectInPreview(tester, i);
      }
      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expectInPreview(tester, 2);
        expect(
          tester
              .widget<ReviewBarEditor>(find.byType(ReviewBarEditor))
              .selectedSymbol,
          2,
        );
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

int painterSymbols(WidgetTester tester) =>
    (tester.widget<CustomPaint>(painting).painter! as ScoreNotationPainter)
        .parts
        .single
        .single
        .symbols
        .length;
