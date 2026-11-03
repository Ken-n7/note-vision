import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_page_thumbnail.dart';
import 'package:note_vision/features/editor/presentation/editor_layout_policy.dart';

import '../../support/engraving_fixture.dart';

void main() {
  testWidgets('the import preview lays out the page as the editor does', (
    tester,
  ) async {
    final score = engravingFixture();
    final policy = EditorLayoutPolicy.forScore(score);
    // A dense bar narrows the row, so the old fixed grid would differ.
    expect(policy.measuresPerRow, lessThan(4));
    await tester.pumpWidget(
      MaterialApp(
        home: ScorePageThumbnail(score: score, pageIndex: 0, cardWidth: 300),
      ),
    );
    final viewer = tester.widget<ScoreNotationViewer>(
      find.byType(ScoreNotationViewer),
    );
    expect(viewer.measuresPerRow, policy.measuresPerRow);
    expect(viewer.minMeasureWidth, policy.minMeasureWidth);
    expect(tester.takeException(), isNull);
  });
}
