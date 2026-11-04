import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';

Future<List<int>> render({required Clef clef, bool notation = true}) async {
  final recorder = ui.PictureRecorder();
  ScoreNotationPainter(
    parts: [
      [
        for (var i = 0; i < 2; i++)
          Measure(
            number: i + 1,
            clef: clef,
            timeSignature: notation
                ? TimeSignature(beats: i == 0 ? 4 : 3, beatType: 4)
                : null,
            symbols: notation
                ? const [Rest(duration: 2, type: 'quarter')]
                : const [],
          ),
      ],
    ],
    measuresPerRow: 2,
    minMeasureWidth: 220,
    rowHeight: 200,
    padding: const EdgeInsets.all(20),
    rowPrefixWidth: 80,
    tabTunings: clef == Clef.tab
        ? const {
            0: [40, 45, 50, 55, 59, 64],
          }
        : const {},
  ).paint(Canvas(recorder), const Size(600, 240));
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 240);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  final result = List<int>.of(bytes);
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'TAB hides rests and initial and changed meters on the canvas',
    () async {
      expect(
        await render(clef: Clef.tab),
        await render(clef: Clef.tab, notation: false),
      );
      const treble = Clef(sign: 'G', line: 2);
      expect(
        await render(clef: treble),
        isNot(await render(clef: treble, notation: false)),
      );
    },
  );

  test('hidden TAB meter changes reserve no signature space', () {
    const measures = [
      Measure(
        number: 1,
        clef: Clef.tab,
        timeSignature: TimeSignature(beats: 4, beatType: 4),
        symbols: [],
      ),
      Measure(
        number: 2,
        timeSignature: TimeSignature(beats: 3, beatType: 4),
        symbols: [],
      ),
    ];
    for (var i = 0; i < measures.length; i++) {
      expect(ScoreNotationMetrics.showsTimeSignature(measures, i), isFalse);
      expect(
        ScoreNotationMetrics.timeSignatureInMeasure(
          measures,
          i,
          measureInRow: i,
          rowPrefixWidth: 20,
        ),
        isFalse,
      );
    }
  });
}
