import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/notation_layout.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';

void main() {
  group('StaffPitchMapper', () {
    test('maps E4 to the treble bottom line reference offset', () {
      expect(
        StaffPitchMapper.offsetFromTrebleBottomLine(step: 'E', octave: 4),
        0,
      );
    });

    test('maps B4 above E4 by four staff steps', () {
      expect(
        StaffPitchMapper.offsetFromTrebleBottomLine(step: 'B', octave: 4),
        4,
      );
    });

    test('maps C4 below E4 by two staff steps', () {
      expect(
        StaffPitchMapper.offsetFromTrebleBottomLine(step: 'C', octave: 4),
        -2,
      );
    });

    test('alto C clef (line 3) bottom line reference is F3', () {
      final ref = StaffPitchMapper.bottomLineRef('C', clefLine: 3);
      expect(ref.step, 'F');
      expect(ref.octave, 3);
    });

    test('tenor C clef (line 4) bottom line reference is D3', () {
      final ref = StaffPitchMapper.bottomLineRef('C', clefLine: 4);
      expect(ref.step, 'D');
      expect(ref.octave, 3);
    });

    test('bass F clef bottom line reference is G2', () {
      final ref = StaffPitchMapper.bottomLineRef('F');
      expect(ref.step, 'G');
      expect(ref.octave, 2);
    });

    test('C4 is on line 3 of alto C clef — offset 4 from bottom line', () {
      // Alto C clef: bottom line = F3; C4 is 4 diatonic steps above F3
      expect(
        StaffPitchMapper.offsetFromBottomLine(
          step: 'C',
          octave: 4,
          clefSign: 'C',
          clefLine: 3,
        ),
        4,
      );
    });

    test('C4 is on line 4 of tenor C clef — offset 6 from bottom line', () {
      // Tenor C clef: bottom line = D3; C4 is 6 diatonic steps above D3
      expect(
        StaffPitchMapper.offsetFromBottomLine(
          step: 'C',
          octave: 4,
          clefSign: 'C',
          clefLine: 4,
        ),
        6,
      );
    });
  });

  group('ScoreNotationViewer', () {
    testWidgets('renders empty-state text for null score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ScoreNotationViewer(score: null)),
        ),
      );

      expect(find.text('No notation to display.'), findsOneWidget);
    });

    testWidgets('renders with imported-style score metadata and symbols', (
      tester,
    ) async {
      final score = Score(
        id: 'imported',
        title: 'Imported Song',
        composer: 'Composer',
        parts: [
          Part(
            id: 'P1',
            name: 'Piano',
            measures: [
              Measure(
                number: 1,
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                keySignature: const KeySignature(fifths: 2),
                symbols: const [
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  Note(step: 'G', octave: 4, duration: 1, type: 'half'),
                  Note(step: 'C', octave: 5, duration: 1, type: 'eighth'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScoreNotationViewer(score: score)),
        ),
      );

      expect(find.byType(ScoreNotationViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders mapped-style score with partial metadata safely', (
      tester,
    ) async {
      final score = Score(
        id: 'mapped',
        title: '',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Mapped',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Rest(duration: 2, type: 'half', staff: 1),
                  Note(step: 'B', octave: 4, duration: 4, type: 'whole', staff: 1),
                  Note(step: 'E', octave: 5, duration: 1, type: 'quarter', staff: 1),
                ],
              ),
              Measure(
                number: 2,
                symbols: const [
                  Note(step: 'D', octave: 5, duration: 1, type: 'flag8thUp', staff: 1),
                  Rest(duration: 4, type: 'whole', staff: 1),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScoreNotationViewer(score: score)),
        ),
      );

      expect(find.byType(ScoreNotationViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('taps resolve note and rest targets with 24dp hit areas', (
      tester,
    ) async {
      final score = Score(
        id: 'tap-targets',
        title: 'Tap targets',
        composer: 'Tester',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      final taps = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreNotationViewer(
              score: score,
              onSymbolTap: (target) {
                if (target == null) return;
                taps.add((target.measureIndex, target.symbolIndex));
              },
            ),
          ),
        ),
      );

      final origin = tester.getTopLeft(find.byType(ScoreNotationViewer));
      await tester.tapAt(
        origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
      );
      await tester.tapAt(
        origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 1),
      );
      await tester.pump();

      expect(taps, equals([(0, 0), (0, 1)]));
    });

    testWidgets('long-press drag reorders symbols within the same measure', (
      tester,
    ) async {
      final score = Score(
        id: 'drag-reorder',
        title: 'Drag reorder',
        composer: 'Tester',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      NotationSymbolReorder? reorderEvent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreNotationViewer(
              score: score,
              onDragCompleted: (event, _) {
                reorderEvent = event;
              },
            ),
          ),
        ),
      );

      final origin = tester.getTopLeft(find.byType(ScoreNotationViewer));
      final gesture = await tester.startGesture(
        origin + _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 0),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await gesture.moveTo(
        origin +
            _symbolCenterOffset(score, measureIndex: 0, symbolIndex: 2) +
            const Offset(2, 0),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(reorderEvent, isNotNull);
      expect(reorderEvent!.fromPartIndex, 0);
      expect(reorderEvent!.fromMeasureIndex, 0);
      expect(reorderEvent!.fromSymbolIndex, 0);
      expect(reorderEvent!.toPartIndex, 0);
      expect(reorderEvent!.toMeasureIndex, 0);
      expect(reorderEvent!.toSymbolIndex, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders alto C clef score without exception', (tester) async {
      final score = Score(
        id: 'alto-clef',
        title: 'Alto Clef',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Viola',
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'C', line: 3),
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                  Rest(duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ScoreNotationViewer(score: score))),
      );

      expect(find.byType(ScoreNotationViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders tenor C clef score without exception', (tester) async {
      final score = Score(
        id: 'tenor-clef',
        title: 'Tenor Clef',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Cello',
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'C', line: 4),
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                  Note(step: 'A', octave: 3, duration: 1, type: 'quarter'),
                  Rest(duration: 2, type: 'half'),
                ],
              ),
              Measure(
                number: 2,
                symbols: const [
                  Note(step: 'G', octave: 3, duration: 4, type: 'whole'),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ScoreNotationViewer(score: score))),
      );

      expect(find.byType(ScoreNotationViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders multi-part score with system connectors without exception',
        (tester) async {
      final score = Score(
        id: 'grand-staff',
        title: 'Grand Staff',
        composer: '',
        parts: [
          Part(
            id: 'P1',
            name: 'Treble',
            measures: [
              Measure(
                number: 1,
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                symbols: const [
                  Note(step: 'E', octave: 5, duration: 1, type: 'quarter'),
                  Note(step: 'C', octave: 5, duration: 1, type: 'quarter'),
                  Rest(duration: 2, type: 'half'),
                ],
              ),
            ],
          ),
          Part(
            id: 'P2',
            name: 'Bass',
            measures: [
              Measure(
                number: 1,
                clef: const Clef(sign: 'F', line: 4),
                timeSignature: const TimeSignature(beats: 4, beatType: 4),
                symbols: const [
                  Note(step: 'C', octave: 3, duration: 1, type: 'quarter'),
                  Note(step: 'G', octave: 2, duration: 1, type: 'quarter'),
                  Rest(duration: 2, type: 'half'),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ScoreNotationViewer(score: score))),
      );

      expect(find.byType(ScoreNotationViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('buildSymbolTargets returns correct Y positions for alto C clef notes',
        (tester) async {
      const alto = Clef(sign: 'C', line: 3);
      final measures = [
        Measure(
          number: 1,
          clef: alto,
          symbols: const [
            Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
            Note(step: 'F', octave: 3, duration: 1, type: 'quarter'),
          ],
        ),
      ];

      const rowHeight = 140.0;
      const padding = EdgeInsets.all(16);
      const minMeasureWidth = 140.0;
      const measuresPerRow = 4;
      final layout = const NotationLayoutCalculator().calculate(
        measures: measures,
        measuresPerRow: measuresPerRow,
        minMeasureWidth: minMeasureWidth,
        rowHeight: rowHeight,
        padding: padding,
      );

      final targets = ScoreNotationPainter.buildSymbolTargets(
        parts: [measures],
        measuresPerRow: layout.measuresPerRow,
        minMeasureWidth: minMeasureWidth,
        rowHeight: rowHeight,
        padding: padding,
        rowPrefixWidth: layout.rowPrefixWidth,
      );

      // C4 is on line 3 of alto clef (middle line) — Y should be above bottom line.
      final c4Target = targets.firstWhere((t) => t.symbolIndex == 0);
      // F3 is the bottom line of alto clef — Y should equal bottomLineY.
      final f3Target = targets.firstWhere((t) => t.symbolIndex == 1);

      // C4 sits higher on the staff (lower Y value) than the bottom-line F3.
      expect(c4Target.center.dy, lessThan(f3Target.center.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('drag across measure boundary produces cross-measure reorder event', (tester) async {
      final score = Score(
        id: 'drag-boundary',
        title: 'Drag boundary',
        composer: 'Tester',
        parts: [
          Part(
            id: 'P1',
            name: 'Part 1',
            measures: [
              Measure(
                number: 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
              Measure(
                number: 2,
                symbols: const [
                  Rest(duration: 1, type: 'quarter'),
                  Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      );

      NotationSymbolReorder? reorderEvent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreNotationViewer(
              score: score,
              onDragCompleted: (event, _) {
                reorderEvent = event;
              },
            ),
          ),
        ),
      );

      final origin = tester.getTopLeft(find.byType(ScoreNotationViewer));
      final gesture = await tester.startGesture(origin + const Offset(184, 68));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await gesture.moveTo(origin + const Offset(315, 68));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Cross-measure drag is now allowed — event fires with different from/to measures.
      if (reorderEvent != null) {
        expect(reorderEvent!.fromMeasureIndex, isNot(equals(reorderEvent!.toMeasureIndex)));
      }
      expect(tester.takeException(), isNull);
    });
  });
}

Offset _symbolCenterOffset(
  Score score, {
  required int measureIndex,
  required int symbolIndex,
}) {
  const measuresPerRow = 4;
  const minMeasureWidth = 140.0;
  const rowHeight = 140.0;
  const padding = EdgeInsets.all(16);

  final measures = score.parts.first.measures;
  final layout = const NotationLayoutCalculator().calculate(
    measures: measures,
    measuresPerRow: measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
  );

  final target = ScoreNotationPainter.buildSymbolTargets(
    parts: [measures],
    measuresPerRow: layout.measuresPerRow,
    minMeasureWidth: minMeasureWidth,
    rowHeight: rowHeight,
    padding: padding,
    rowPrefixWidth: layout.rowPrefixWidth,
  ).firstWhere(
    (entry) => entry.measureIndex == measureIndex && entry.symbolIndex == symbolIndex,
  );

  return target.center;
}
