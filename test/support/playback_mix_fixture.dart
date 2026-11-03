import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';

Score ensemble({int count = 2, bool linked = false}) => Score(
  id: 'mix',
  title: 'Mix',
  composer: '',
  playbackLayout: ScorePlaybackLayout.simultaneousParts,
  parts: [
    for (var i = 0; i < count; i++)
      Part(
        id: 'P${i + 1}',
        name: 'Staff ${i + 1}',
        staff: linked && i == 1 ? 2 : 1,
        measures: [
          Measure(
            number: 1,
            symbols: const [
              Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
            ],
          ),
        ],
      ),
  ],
);
