import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/features/collection/presentation/widgets/score_card.dart';

void main() {
  testWidgets('ScoreCard renders an image fallback inside ClipRRect', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 300,
            child: ScoreCard(imagePath: '/fake/path/image.jpg'),
          ),
        ),
      ),
    );

    expect(find.byType(ScoreCard), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clipRRect.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('ScoreCard renders notation preview when score is loaded', (
    WidgetTester tester,
  ) async {
    final score = Score(
      id: 'score',
      title: 'Loaded Score',
      composer: 'Composer',
      parts: const [
        Part(
          id: 'P1',
          name: 'Part 1',
          measures: [
            Measure(number: 1, symbols: [Rest(duration: 2, type: 'quarter')]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 300,
            child: ScoreCard(
              imagePath: '/fake/path/image.jpg',
              score: score,
              scoreLabel: 'Simple Melody',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ScorePageThumbnail), findsOneWidget);
    expect(find.text('Loaded Score'), findsOneWidget);
    expect(find.text('Composer'), findsOneWidget);
    expect(find.text('Simple Melody'), findsOneWidget);
  });
}
