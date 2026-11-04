import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part_playback.dart';

/// [distinct] gives each staff its own sound, so none share a channel.
Score ensemble({int count = 2, bool linked = false, bool distinct = false}) =>
    Score(
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
            playback: PartPlayback(program: distinct ? i : 0),
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
