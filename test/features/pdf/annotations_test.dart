import 'dart:io';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/annotation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import '../../support/editor_controls_harness.dart';

Score fixture() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File(
      'test/musescore_parity/cases/12_text_chord_symbols.musicxml',
    ).readAsStringSync(),
  ),
);
void main() {
  setUpAll(loadControlsFonts);
  testWidgets('text/tempo/chord hit targets select their original marking', (
    tester,
  ) async {
    final score = fixture();
    (int, int, int)? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ScoreNotationViewer(
              score: score,
              measuresPerRow: 2,
              minMeasureWidth: 280,
              onAnnotationTap: (p, m, i) => selected = (p, m, i),
            ),
          ),
        ),
      ),
    );
    final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ScoreNotationPainter,
    );
    final p =
        tester.widget<CustomPaint>(canvas).painter! as ScoreNotationPainter;
    final targets = ScoreNotationPainter.buildAnnotationTargets(
      parts: p.parts,
      allParts: p.lyricParts!,
      firstMeasureIndex: 0,
      measuresPerRow: p.measuresPerRow,
      minMeasureWidth: p.minMeasureWidth,
      rowHeight: p.rowHeight,
      padding: p.padding,
      rowPrefixWidth: p.rowPrefixWidth,
    );
    expect(targets, hasLength(7));
    final target = targets.firstWhere((t) => t.$2 == 1 && t.$3 == 0);
    await tester.tapAt(tester.getTopLeft(canvas) + target.$4.center);
    expect(selected, (0, 1, 0));
    expect(tester.takeException(), isNull);
  });
  test('system text on a lower part routes to the top staff', () {
    final parts = [
      [const Measure(number: 1, symbols: [])],
      [
        const Measure(
          number: 1,
          symbols: [],
          annotations: [
            ScoreAnnotation(
              kind: AnnotationKind.systemText,
              text: 'All staves',
            ),
            ScoreAnnotation(kind: AnnotationKind.staffText, text: 'Lower only'),
          ],
        ),
      ],
    ];
    expect(AnnotationLayout.at(parts, 0, 0).single.$3.text, 'All staves');
    expect(AnnotationLayout.at(parts, 1, 0).single.$3.text, 'Lower only');
  });
  test(
    'PDF renders text and chords with the editor pagination policy',
    () async {
      final score = fixture();
      const renderer = PdfScoreRenderer(compress: false);
      final bytes = await renderer.render(score);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(
        renderer.debugPageLayoutForTesting(score).first.rowsPerPage,
        EditorLayoutPolicy.forScore(score).rowsPerPage,
      );
      final directory = Platform.environment['NV_EDITOR_SCREENSHOTS'];
      if (directory != null) {
        await Directory(directory).create(recursive: true);
        await File('$directory/annotations.pdf').writeAsBytes(bytes);
      }
    },
  );
  test('new empty bars do not copy text/chords from their predecessor', () {
    final s = fixture().insertMeasureAfterInAllParts(0);
    expect(s.parts.first.measures[1].annotations, isEmpty);
    expect(s.parts.first.measures[0].annotations, isNotEmpty);
    final score = Score(
      id: 'large',
      title: '',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [
            for (var i = 0; i < 21; i++)
              s.parts.first.measures.first.copyWith(number: i + 1),
          ],
        ),
      ],
    );
    final pages = const PdfScoreRenderer().debugPageLayoutForTesting(score);
    final policy = EditorLayoutPolicy.forScore(score);
    expect(
      pages.map((p) => p.firstMeasureIndex),
      pageStartIndicesForMeasures(
        score.parts.first.measures,
        layoutPolicy: policy,
      ),
    );
  });
}
