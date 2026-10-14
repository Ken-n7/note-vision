import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';

void main() {
  const fourFour = TimeSignature(beats: 4, beatType: 4);
  const threeFour = TimeSignature(beats: 3, beatType: 4);

  Part part(String id) => Part(
        id: id,
        name: id,
        measures: [
          const Measure(number: 1, timeSignature: fourFour, symbols: []),
          for (var n = 2; n <= 3; n++) Measure(number: n, symbols: const []),
        ],
      );

  final score = Score(
    id: 's',
    title: 't',
    composer: 'c',
    parts: [part('upper'), part('lower')],
  );

  test('sets the time signature on the selected measure of every part', () {
    final state = EditorState(score: score)
        .copyWith(selectedPartIndex: 0, selectedMeasureIndex: 1);
    expect(state.selectedMeasureTimeSignature, fourFour);

    final changed = state.setTimeSignatureAtSelectedMeasure(threeFour);

    for (final p in changed.score.parts) {
      expect(p.measures.map((m) => m.timeSignature), [fourFour, threeFour, null]);
    }
    expect(changed.selectedMeasureTimeSignature, threeFour);
    expect(
      changed.copyWith(selectedMeasureIndex: 2).selectedMeasureTimeSignature,
      threeFour,
      reason: 'it holds until the next measure that sets one',
    );
    expect(changed.undo().score.parts[1].measures[1].timeSignature, isNull);
  });

  test('no edit when it is already set, or nothing is selected', () {
    final state = EditorState(score: score)
        .copyWith(selectedPartIndex: 0, selectedMeasureIndex: 0);
    expect(state.setTimeSignatureAtSelectedMeasure(fourFour).undoStack, isEmpty);
    expect(
      EditorState(score: score).setTimeSignatureAtSelectedMeasure(threeFour).score,
      same(score),
    );
  });
}
