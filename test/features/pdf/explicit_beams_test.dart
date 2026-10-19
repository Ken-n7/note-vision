import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/beam_grouping.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_symbol.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

Future<int> beamPolygons(List<ScoreSymbol> symbols) async {
  final score = Score(
    id: 'pdf-beams',
    title: '',
    composer: '',
    parts: [
      Part(
        id: 'P1',
        name: '',
        measures: [
          Measure(
            number: 1,
            clef: const Clef(sign: 'G', line: 2),
            symbols: symbols,
          ),
        ],
      ),
    ],
  );
  final bytes = await const PdfScoreRenderer(compress: false).render(score);
  final content = latin1.decode(bytes);
  // Beams are filled quadrilaterals; noteheads use curves and stems use strokes.
  final coordinate = r'-?[\d.]+ -?[\d.]+';
  return RegExp(
    '$coordinate m\\s+$coordinate l\\s+$coordinate l\\s+$coordinate l\\s+h\\s+f',
  ).allMatches(content).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDF draws two separate adjacent groups instead of a single long beam',
    () async {
      final notes = List<ScoreSymbol>.generate(
        4,
        (_) => const Note(step: 'C', octave: 4, type: 'eighth', duration: 1),
      );
      final connected = BeamGrouping.join(notes, 0, 3);
      final split = BeamGrouping.split(connected, 2, before: true);
      expect(await beamPolygons(connected), 1);
      expect(await beamPolygons(split), 2);
    },
  );

  test(
    'PDF draws both beam levels and preserves imported partial hooks',
    () async {
      final notes = <ScoreSymbol>[
        const Note(step: 'C', octave: 4, type: 'sixteenth', duration: 1),
        const Note(step: 'D', octave: 4, type: 'sixteenth', duration: 1),
      ];
      expect(await beamPolygons(BeamGrouping.join(notes, 0, 1)), 2);
      final hooks = [
        (notes[0] as Note).withBeams({
          1: BeamValue.begin,
          2: BeamValue.forwardHook,
        }),
        (notes[1] as Note).withBeams({
          1: BeamValue.end,
          2: BeamValue.backwardHook,
        }),
      ];
      expect(await beamPolygons(hooks), 3);
    },
  );
}
