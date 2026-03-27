import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
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
  });
}
