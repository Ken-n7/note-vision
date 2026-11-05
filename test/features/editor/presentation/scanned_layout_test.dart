import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_display_projection.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

import '../../../support/editor_controls_harness.dart';

Score scannedPage() => Score.fromJson(
  jsonDecode(
        File(
          'test/fixtures/real_scans/page_211254_063.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

Score shortRows({List<int> lengths = const [1, 3], bool pages = false}) =>
    Score(
      id: 'mapped-score',
      title: '',
      composer: '',
      parts: [
        for (final (p, count) in lengths.indexed)
          Part(
            id: 'p$p',
            name: 'Line ${p + 1}',
            measures: [
              for (var m = 0; m < count; m++)
                Measure(
                  number: m + 1,
                  clef: p == 0 && m == 0
                      ? const Clef(sign: 'F', line: 4)
                      : null,
                  keySignature: p == 0 && m == 0
                      ? const KeySignature(fifths: -2)
                      : null,
                  timeSignature: p == 0 && m == 0
                      ? const TimeSignature(beats: 3, beatType: 4)
                      : null,
                  symbols: [
                    Note(
                      step: p == 0 ? 'C' : 'E',
                      octave: 4,
                      type: 'quarter',
                      duration: 2,
                      source: SourceRegion(
                        pageId: pages ? 'page$p' : '',
                        x: 0,
                        y: 0,
                        width: .1,
                        height: .1,
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

ScoreNotationPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<ScoreNotationPainter>()
    .single;

Future<void> tapCell(WidgetTester tester, int measure, int symbol) async {
  final p = painter(tester);
  final target = ScoreNotationPainter.buildSymbolTargets(
    parts: p.parts,
    measuresPerRow: p.measuresPerRow,
    minMeasureWidth: p.minMeasureWidth,
    rowHeight: p.rowHeight,
    padding: p.padding,
    rowPrefixWidth: p.rowPrefixWidth,
    engraving: p.engraving,
  ).firstWhere((t) => t.measureIndex == measure && t.symbolIndex == symbol);
  final finder = find.byWidgetPredicate(
    (w) => w is CustomPaint && identical(w.painter, p),
  );
  final box = tester.renderObject<RenderBox>(finder);
  await tester.tapAt(box.localToGlobal(target.center));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadControlsFonts);
  test(
    'eight scanned rows retain their three-bar reading order on one page',
    () {
      final score = scannedPage();
      final before = jsonEncode(score.toJson());
      expect(score.parts, hasLength(8));
      final policy = EditorLayoutPolicy.forScore(score);
      expect(policy.measuresPerRow, 3);
      expect(policy.rowsPerPage, greaterThanOrEqualTo(8));
      final measures = layoutMeasuresForScore(score);
      expect(measures, hasLength(24));
      expect(pageStartIndicesForMeasures(measures, layoutPolicy: policy), [0]);
      expect(jsonEncode(score.toJson()), before);
    },
  );

  test('PDF uses the same scanned rows instead of three ensemble columns', () {
    final pages = const PdfScoreRenderer().debugPageLayoutForTesting(
      scannedPage(),
    );
    expect(pages, hasLength(1));
    expect(pages.single.measuresPerSystem, 3);
    expect(pages.single.measureCount, 24);
  });

  test(
    'projection cells map to original rows and keep context independent',
    () {
      final original = shortRows();
      final display = ScoreDisplayProjection.forScore(original);
      expect(display.sequential, isTrue);
      expect(display.columns, 3);
      expect(display.hiddenMeasures, {1, 2});
      expect(display.origin(0, 0), (part: 0, measure: 0));
      expect(display.origin(0, 1), isNull);
      expect(display.origin(0, 3), (part: 1, measure: 0));
      expect(display.index(1, 2), 5);
      final measures = EngravingLayout.forScore(display.score).parts.single;
      expect(measures[3].clef?.sign, 'G');
      expect(measures[3].keySignature, isNull);
      expect(measures[3].timeSignature, isNull);
      expect(
        EngravingLayout.forScore(display.score).bars[3].duration,
        MusicalTime.one,
      );
      final slice = sliceScoreForLayout(
        score: display.score,
        firstMeasureIndex: 3,
        pageMeasureCount: 3,
      );
      expect(slice.parts.single.first.timeSignature, isNull);
    },
  );

  test(
    'source page boundaries paginate without transposing row/column order',
    () {
      final original = shortRows(lengths: [2, 3], pages: true);
      final policy = EditorLayoutPolicy.forScore(original);
      final measures = layoutMeasuresForScore(original);
      expect(pageStartIndicesForMeasures(measures, layoutPolicy: policy), [
        0,
        3,
      ]);
      final pages = const PdfScoreRenderer().debugPageLayoutForTesting(
        original,
      );
      expect(pages.map((p) => p.firstMeasureIndex), [0, 3]);
    },
  );

  test(
    'independent rows repeat their meter without inventing a missing one',
    () {
      final original = shortRows();
      final score = original.copyWith(
        parts: [
          original.parts.first,
          original.parts.last.copyWith(
            measures: [
              original.parts.last.measures.first.copyWith(
                timeSignature: const TimeSignature(beats: 3, beatType: 4),
              ),
            ],
          ),
        ],
      );
      final display = ScoreDisplayProjection.forScore(score);
      final measures = EngravingLayout.forScore(display.score).parts.single;
      expect(ScoreNotationMetrics.showsTimeSignature(measures, 0), isTrue);
      expect(ScoreNotationMetrics.showsTimeSignature(measures, 1), isTrue);
      final unknown = ScoreDisplayProjection.forScore(original);
      expect(
        ScoreNotationMetrics.showsTimeSignature(
          unknown.score.parts.single.measures,
          3,
        ),
        isFalse,
      );
    },
  );

  test('real scan PDF renders a complete page', () async {
    final bytes = await const PdfScoreRenderer().render(scannedPage());
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['NV_EDITOR_SCREENSHOTS'];
    if (out != null) {
      Directory(out).createSync(recursive: true);
      File('$out/scanned-rows.pdf').writeAsBytesSync(bytes);
    }
  });

  test('ensembles and grand staves retain their instrument layout', () {
    final ensemble = buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates
            .firstWhere((t) => t.name == 'Symphony orchestra')
            .staves,
        bars: 3,
      ),
    );
    expect(ScoreDisplayProjection.forScore(ensemble).score, same(ensemble));
    final grand = shortRows().copyWith(
      parts: [
        shortRows().parts.first,
        shortRows().parts.last.copyWith(staff: 2),
      ],
    );
    expect(ScoreDisplayProjection.forScore(grand).score, same(grand));
  });

  test('layout leaves saved music, playback and MusicXML unchanged', () {
    final original = scannedPage();
    final json = jsonEncode(original.toJson());
    final xml = const MusicXmlExportService().toMusicXml(original);
    final midi = const PlaybackConverter().buildEvents(original);
    final display = ScoreDisplayProjection.forScore(original);
    EditorLayoutPolicy.forScore(original);
    expect(display.origins!.whereType<ScoreCell>(), hasLength(24));
    expect(jsonEncode(original.toJson()), json);
    expect(const MusicXmlExportService().toMusicXml(original), xml);
    expect(const PlaybackConverter().buildEvents(original), midi);
  });

  testWidgets('touching row 2 edits its original part and undo restores it', (
    tester,
  ) async {
    final (_, storage) = await pumpControls(
      tester,
      score: scannedPage(),
      existingProject: true,
    );
    await save(tester);
    final before = storage.saved.last.decodeScore();
    await tapCell(tester, 3, 0);
    expect(find.text('Bass · Bar 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await save(tester);
    final after = storage.saved.last.decodeScore();
    expect(after.parts, hasLength(8));
    expect(
      (after.getSymbolAt(1, 0, 0) as Note).pitch,
      isNot((before.getSymbolAt(1, 0, 0) as Note).pitch),
    );
    expect(after.parts.first.toJson(), before.parts.first.toJson());
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(storage.saved.last.decodeScore().toJson(), before.toJson());
    await captureControls(tester, 'scanned-rows-editor');
    expect(tester.takeException(), isNull);
  });

  testWidgets('next and previous symbol cross a scanned row boundary', (
    tester,
  ) async {
    await pumpControls(tester, score: shortRows(), existingProject: true);
    await tester.tap(find.byTooltip('Next symbol'));
    await tester.pumpAndSettle();
    expect(find.text('Line 2 · Bar 1'), findsOneWidget);
    expect(
      tester
          .widget<ScoreNotationViewer>(find.byType(ScoreNotationViewer))
          .selectedMeasureIndex,
      3,
    );
    await tester.tap(find.byTooltip('Previous symbol'));
    await tester.pumpAndSettle();
    expect(find.text('Line 1 · Bar 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'playback highlights the real row without advancing by bar column',
    (tester) async {
      final (playback, _) = await pumpControls(tester, score: scannedPage());
      playback.emitPosition(
        const PlaybackPosition(partIndex: 1, measureIndex: 1, symbolIndex: 0),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      expect(view.playbackPartIndex, 0);
      expect(view.playbackMeasureIndex, 4);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ragged row gaps draw no invented empty bars and accept no input',
    (tester) async {
      final (_, storage) = await pumpControls(
        tester,
        score: shortRows(),
        existingProject: true,
      );
      await save(tester);
      final before = storage.saved.last.scoreJson;
      final p = painter(tester);
      final x = p.padding.left + p.rowPrefixWidth + p.minMeasureWidth * 1.5;
      final y = p.padding.top + 28 + ScoreNotationPainter.staffLineSpacing * 2;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final width =
            (p.padding.horizontal + p.rowPrefixWidth + p.minMeasureWidth * 3)
                .ceil();
        final height = (p.padding.vertical + p.rowHeight * 2).ceil();
        canvas.drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = Colors.white,
        );
        p.paint(canvas, Size(width.toDouble(), height.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (var dy = -2; dy <= 2; dy++) {
          final offset = ((y.round() + dy) * width + x.round()) * 4;
          expect(bytes.getUint8(offset), 255);
          expect(bytes.getUint8(offset + 1), 255);
          expect(bytes.getUint8(offset + 2), 255);
        }
        image.dispose();
        picture.dispose();
      });
      final finder = find.byWidgetPredicate(
        (w) => w is CustomPaint && identical(w.painter, p),
      );
      final box = tester.renderObject<RenderBox>(finder);
      await tester.tapAt(box.localToGlobal(Offset(x, y)));
      await tester.pumpAndSettle();
      await save(tester);
      expect(storage.saved.last.scoreJson, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'structural review previews reflow every scanned row without clipping',
    (tester) async {
      final base = shortRows(lengths: [1, 1]);
      final score = base.copyWith(
        parts: [
          base.parts.first.copyWith(
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'F', line: 4),
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                symbols: [
                  for (var i = 0; i < 12; i++)
                    Note(
                      step: ['C', 'D', 'E', 'F', 'G', 'A', 'B'][i % 7],
                      octave: 3,
                      type: 'quarter',
                      duration: 2,
                      source: SourceRegion(
                        pageId: '',
                        x: i * .04,
                        y: 0,
                        width: .02,
                        height: .1,
                      ),
                    ),
                ],
              ),
            ],
          ),
          base.parts.last.copyWith(
            measures: [
              base.parts.last.measures.first.copyWith(
                clef: const Clef(sign: 'G', line: 2),
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
              ),
            ],
          ),
        ],
      );
      await pumpControls(tester, score: score, existingProject: true);
      await tester.tap(find.byTooltip('Review & Correct'));
      await tester.pumpAndSettle();
      expect(find.text('Split into 3 bars'), findsOneWidget);
      await tester.ensureVisible(find.text('Preview change'));
      await tester.tap(find.text('Preview change'));
      await tester.pumpAndSettle();
      final view = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).first,
      );
      expect(view.measuresPerRow, 3);
      expect(view.pageMeasureCount, 6);
      expect(
        view.score!.parts.single.measures
            .expand((m) => m.symbols)
            .whereType<Note>(),
        hasLength(13),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scan thumbnails use the same row order as the editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScorePageThumbnail(
          score: scannedPage(),
          pageIndex: 0,
          cardWidth: 300,
        ),
      ),
    );
    final view = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer),
    );
    expect(view.score!.parts, hasLength(1));
    expect(view.score!.parts.single.measures, hasLength(24));
    expect(view.measuresPerRow, 3);
    expect(tester.takeException(), isNull);
  });
}
