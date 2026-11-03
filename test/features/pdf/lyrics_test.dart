import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/musicXML/musicxml_score_converter.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';
import 'package:xml/xml.dart';
import '../../support/editor_controls_harness.dart';

Score fixture() => const MusicXmlScoreConverter().convert(
  XmlDocument.parse(
    File('test/musescore_parity/cases/13_lyrics.musicxml').readAsStringSync(),
  ),
);

void main() {
  setUpAll(loadControlsFonts);
  testWidgets('lyric text selects its owning note', (tester) async {
    final score = fixture();
    NotationSymbolTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ScoreNotationViewer(
              score: score,
              measuresPerRow: 2,
              minMeasureWidth: 280,
              onSymbolTap: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    final canvas = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ScoreNotationPainter,
    );
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as ScoreNotationPainter;
    final targets = ScoreNotationPainter.buildLyricTargets(
      parts: painter.parts,
      lyricParts: painter.lyricParts!,
      firstMeasureIndex: 0,
      measuresPerRow: painter.measuresPerRow,
      minMeasureWidth: painter.minMeasureWidth,
      rowHeight: painter.rowHeight,
      padding: painter.padding,
      rowPrefixWidth: painter.rowPrefixWidth,
    );
    expect(targets, hasLength(7));
    final last = targets.firstWhere(
      (t) => t.measureIndex == 1 && t.symbolIndex == 1,
    );
    await tester.tapAt(tester.getTopLeft(canvas) + last.center);
    expect(
      (selected!.partIndex, selected!.measureIndex, selected!.symbolIndex),
      (0, 1, 1),
    );
  });

  test('PDF renders verse text and extension lines', () async {
    final score = fixture();
    final n = score.parts.first.measures.last.symbols.last as Note;
    final extended = score.replaceSymbolAt(
      0,
      1,
      1,
      n.copyWith(
        lyrics: [const Lyric(text: 'to', extend: LyricExtend.start)],
      ),
    );
    final bytes = await const PdfScoreRenderer(
      compress: false,
    ).render(extended);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final directory = Platform.environment['NV_EDITOR_SCREENSHOTS'];
    if (directory != null) {
      await Directory(directory).create(recursive: true);
      await File('$directory/lyrics.pdf').writeAsBytes(bytes);
    }
  });
}
