import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/core/widgets/score_notation_viewer.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_painter.dart';
import 'package:note_vision/features/editor/presentation/widgets/playback_controls_bar.dart';

import '../../../support/editor_controls_harness.dart';

void main() {
  setUpAll(loadControlsFonts);
  testWidgets(
    'ensemble transport uses shared bars and seeks a staff that has the target bar',
    (tester) async {
      final base = controlsScore();
      final score = base.copyWith(
        playbackLayout: ScorePlaybackLayout.simultaneousParts,
        parts: [
          base.parts.first,
          Part(
            id: 'lower',
            name: 'Lower staff',
            measures: base.parts.first.measures.take(2).toList(),
          ),
        ],
      );
      final (playback, _) = await pumpControls(tester, score: score);
      final controls = tester.widget<PlaybackControlsBar>(
        find.byType(PlaybackControlsBar),
      );
      expect(controls.totalMeasures, 4);
      expect(controls.measureCounts, isNull);
      playback.emitPosition(
        const PlaybackPosition(partIndex: 1, measureIndex: 1, symbolIndex: 0),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1);

      final viewer = tester.widget<ScoreNotationViewer>(
        find.byType(ScoreNotationViewer).first,
      );
      viewer.onSymbolTap!(
        const NotationSymbolTarget(
          partIndex: 1,
          measureIndex: 0,
          symbolIndex: 0,
          center: Offset.zero,
          hitRect: Rect.zero,
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(3);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(3);
      await tester.pumpAndSettle();
      expect(playback.soughtMeasure, 3);
      expect(playback.soughtPart, 0);
    },
  );
}
