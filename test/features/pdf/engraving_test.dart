import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/widgets/score_notation/engraving_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import '../../support/engraving_fixture.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (name, path) in [
      ('NotoSans', 'assets/fonts/NotoSans-Regular.ttf'),
      ('NotoMusic', 'assets/fonts/NotoMusic-Regular.ttf'),
    ]) {
      await (FontLoader(name)..addFont(rootBundle.load(path))).load();
    }
  });
  test('engraving PDF renders with adaptive page layout', () async {
    final score = engravingFixture();
    final bytes = await const PdfScoreRenderer().render(score);
    expect(bytes.length, greaterThan(1000));
    final directory = Platform.environment['NV_EDITOR_SCREENSHOTS'];
    if (directory != null) {
      Directory(directory).createSync(recursive: true);
      File('$directory/engraving.pdf').writeAsBytesSync(bytes);
      File(
        '$directory/engraving.musicxml',
      ).writeAsStringSync(const MusicXmlExportService().toMusicXml(score));
    }
  });
  testWidgets(
    'engraved heads remain selectable and editor/PDF share page grouping',
    (tester) async {
      final score = engravingFixture(),
          policy = EditorLayoutPolicy.forScore(engravingFixture());
      tester.view.physicalSize = Size(policy.pageWidth, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      NotationSymbolTarget? selected;
      const key = ValueKey('engraving-capture');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: ScoreNotationViewer(
                  score: score,
                  measuresPerRow: policy.measuresPerRow,
                  minMeasureWidth: policy.minMeasureWidth,
                  rowHeight: policy.rowHeight,
                  padding: EdgeInsets.symmetric(
                    horizontal: policy.horizontalPadding,
                    vertical: policy.verticalPadding,
                  ),
                  onSymbolTap: (target) => selected = target,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer),
      );
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(ScoreNotationViewer),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((p) => p.painter)
          .whereType<ScoreNotationPainter>()
          .single;
      final targets = ScoreNotationPainter.buildSymbolTargets(
        parts: painter.parts,
        measuresPerRow: policy.measuresPerRow,
        minMeasureWidth: policy.minMeasureWidth,
        rowHeight: policy.rowHeight,
        padding: painter.padding,
        rowPrefixWidth: policy.rowPrefixWidth,
        engraving: EngravingLayout.forScore(score),
      );
      // A displaced chord tone must be hit where it was actually painted.
      final target = targets.firstWhere(
        (t) => t.measureIndex == 3 && t.symbolIndex == 1,
      );
      await tester.ensureVisible(find.byType(ScoreNotationViewer));
      final offset = tester.getTopLeft(find.byType(ScoreNotationViewer));
      await tester.tapAt(offset + target.center);
      await tester.pump();
      expect(selected?.symbolIndex, 1);
      expect(selected?.measureIndex, 3);
      expect(tester.takeException(), isNull);
      final pdf = const PdfScoreRenderer().debugPageLayoutForTesting(score);
      expect(pdf.first.measuresPerSystem, policy.measuresPerRow);
      expect(pdf.first.rowsPerPage, policy.rowsPerPage);
      expect(viewer.score, same(score));
      final directory = Platform.environment['NV_EDITOR_SCREENSHOTS'];
      if (directory != null) {
        Directory(directory).createSync(recursive: true);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final capture = await boundary.toImage(pixelRatio: 2);
          final bytes = await capture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File(
            '$directory/engraving-canvas.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          capture.dispose();
        });
      }
    },
  );
}
