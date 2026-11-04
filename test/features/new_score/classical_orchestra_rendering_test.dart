import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/features/new_score/new_score.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

import '../../support/editor_controls_harness.dart' show loadControlsFonts;

void main() {
  setUpAll(loadControlsFonts);
  testWidgets('horn square bracket changes canvas ink and exports to PDF', (
    tester,
  ) async {
    final orchestra = buildNewScore(
      NewScoreOptions(
        staves: scoreTemplates
            .firstWhere((t) => t.name == 'Classical orchestra')
            .staves,
        bars: 1,
      ),
    );
    final horns = orchestra.copyWith(
      parts: orchestra.parts.where((p) => p.name == 'Horns in F').toList(),
    );
    final boundaryKey = GlobalKey();
    Future<Uint8List> capture(bool square) async {
      final score = horns.copyWith(
        parts: [
          horns.parts.first,
          horns.parts.last.copyWith(squareBracket: square),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ScoreNotationViewer(
                score: score,
                measuresPerRow: 1,
                minMeasureWidth: 260,
                rowHeight: 160,
                padding: const EdgeInsets.all(28),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        return bytes;
      }))!;
    }

    final square = await capture(true);
    final brace = await capture(false);
    expect(square, isNot(brace));
    final pdf = (await tester.runAsync(
      () => const PdfScoreRenderer().render(horns),
    ))!;
    expect(pdf.take(4), [37, 80, 68, 70]);
    final output = Platform.environment['NV_EDITOR_SCREENSHOTS'];
    if (output != null) {
      await tester.runAsync(() async {
        await Directory(output).create(recursive: true);
        await File('$output/classical-horns-square.png').writeAsBytes(square);
        await File('$output/classical-horns-brace.png').writeAsBytes(brace);
        await File('$output/classical-horns.pdf').writeAsBytes(pdf);
        await File(
          '$output/classical-orchestra.pdf',
        ).writeAsBytes(await const PdfScoreRenderer().render(orchestra));
      });
    }
    expect(tester.takeException(), isNull);
  });
}
