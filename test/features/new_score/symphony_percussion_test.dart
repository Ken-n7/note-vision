import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/drum_kit.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

import '../../support/editor_controls_harness.dart';

Score orchestra() => buildNewScore(
  NewScoreOptions(
    staves: scoreTemplates
        .firstWhere((t) => t.name == 'Symphony orchestra')
        .staves,
    bars: 3,
    title: 'Symphony orchestra',
    composer: 'QA Composer',
  ),
);

void main() {
  setUpAll(loadControlsFonts);
  testWidgets('renaming and moving a new snare keeps its one-line instrument', (
    tester,
  ) async {
    final full = orchestra();
    final score = full.copyWith(
      parts: full.parts.where((p) => p.name == 'Flute 1').toList(),
    );
    await pumpControls(tester, score: score, selectedSymbol: null);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staves and instruments…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add instrument'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Snare Drum · Percussion clef'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snare Drum · Percussion clef'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snare Drum'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('staff-name-field')),
      'Side drum',
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move up').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final added = shownControlsScore(tester).parts.first;
    expect(added.name, 'Side drum');
    expect(added.singleLine, isTrue);
    expect(added.playback.program, 48);
    expect(added.drums.map((d) => d.key), [38, 37]);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(shownControlsScore(tester).parts.single.name, 'Flute 1');
  });
  for (final (name, key, size, scale) in [
    ('Snare Drum', 38, const Size(390, 844), 1.0),
    ('Bass Drum', 36, const Size(844, 390), 1.0),
    ('Cymbals', 57, const Size(320, 568), 2.0),
  ]) {
    testWidgets('$name uses its own touch palette and shortcuts', (
      tester,
    ) async {
      final full = orchestra();
      final score = full.copyWith(
        parts: full.parts.where((p) => p.name == name).toList(),
      );
      await pumpControls(
        tester,
        score: score,
        selectedSymbol: null,
        size: size,
        textScale: scale,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      final piece = score.parts.first.drums.first;
      final chip = find.byTooltip('Enter ${piece.name} (${piece.shortcut})');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      List<Note> notes() => shownControlsScore(
        tester,
      ).parts.first.measures.first.symbols.whereType<Note>().toList();
      expect(notes().single.drum, key);
      expect(
        (notes().single.step, notes().single.octave, notes().single.voice ?? 1),
        ('B', 4, 1),
      );
      expect(find.byTooltip('Enter Closed Hi-Hat (C)'), findsNothing);
      if (name == 'Snare Drum') {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pumpAndSettle();
        expect(notes().map((n) => (n.drum, n.notehead)), [
          (38, null),
          (37, 'x'),
        ]);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.pumpAndSettle();
        expect(notes(), hasLength(2));
      }
      final beforeTouch = notes().length;
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).first,
      );
      viewer.onInsertTap!(
        NotationInsertTarget(
          partIndex: 0,
          measureIndex: 0,
          insertIndex: shownControlsScore(
            tester,
          ).parts.first.measures.first.symbols.length,
          indicatorX: 200,
          step: 'F',
          octave: 7,
        ),
      );
      await tester.pumpAndSettle();
      expect(notes(), hasLength(beforeTouch + 1));
      expect(notes().last.drum, key);
      expect((notes().last.step, notes().last.octave), ('B', 4));
      await captureControls(tester, 'symphony-$key-entry');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(notes(), hasLength(beforeTouch));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'one-line percussion renders notes, rests, beams and repeat bars',
    (tester) async {
      final full = orchestra();
      final score = full.copyWith(
        parts: [
          for (final p in full.parts.where((p) => p.singleLine))
            p.copyWith(
              measures: [
                p.measures[0].copyWith(
                  symbols: [
                    drumNote(p.drums.first, 'eighth', 1).copyWith(beamed: true),
                    drumNote(p.drums.last, 'eighth', 1).copyWith(beamed: true),
                  ],
                ),
                p.measures[1].copyWith(
                  symbols: [
                    const Rest(duration: 8, type: 'whole', measureRest: true),
                  ],
                ),
                p.measures[2].copyWith(
                  rightBarlineType: BarlineType.repeatEnd,
                  symbols: [
                    const Rest(duration: 4, type: 'half'),
                    const Rest(duration: 2, type: 'quarter'),
                    const Rest(duration: 1, type: 'eighth'),
                    const Rest(duration: 1, type: 'eighth'),
                  ],
                ),
              ],
            ),
        ],
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ScoreNotationViewer(
                score: score,
                measuresPerRow: 3,
                minMeasureWidth: 190,
                rowHeight: 150,
                padding: const EdgeInsets.all(28),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final targets = ScoreNotationPainter.buildSymbolTargets(
        parts: score.parts.map((p) => p.measures).toList(),
        measuresPerRow: 3,
        minMeasureWidth: 190,
        rowHeight: 150,
        padding: const EdgeInsets.all(28),
        rowPrefixWidth: 80,
        singleLineParts: {0, 1, 2},
      );
      final note = targets.first;
      final rest = targets.firstWhere(
        (t) => t.partIndex == 0 && t.measureIndex == 1,
      );
      expect(
        rest.center.dy,
        note.center.dy + ScoreNotationMetrics.wholeRestCenterYOffset,
      );
      final pdf = (await tester.runAsync(
        () => const PdfScoreRenderer().render(score),
      ))!;
      expect(pdf.take(4), [37, 80, 68, 70]);
      final output = Platform.environment['NV_EDITOR_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          image.dispose();
          await Directory(output).create(recursive: true);
          await File('$output/symphony-percussion.png').writeAsBytes(bytes);
          await File('$output/symphony-percussion.pdf').writeAsBytes(pdf);
          await File(
            '$output/symphony-orchestra.pdf',
          ).writeAsBytes(await const PdfScoreRenderer().render(full));
        });
      }
      expect(tester.takeException(), isNull);
    },
  );
}
