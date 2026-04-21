import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/features/collection/presentation/widgets/score_card.dart';

void main() {
  testWidgets('ScoreCard renders an image inside ClipRRect', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScoreCard(imagePath: '/fake/path/image.jpg')),
      ),
    );

    expect(find.byType(ScoreCard), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clipRRect.borderRadius, BorderRadius.circular(10));
  });
}
