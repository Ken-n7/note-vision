import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_service.dart';

void main() {
  // Three staves of three bars, one note per bar, read staff by staff.
  final events = const PlaybackConverter().buildEvents(
    Score(
      id: 's',
      title: '',
      composer: '',
      parts: [
        for (var p = 0; p < 3; p++)
          Part(
            id: 'p$p',
            name: 'p$p',
            measures: [
              for (var m = 0; m < 3; m++)
                Measure(
                  number: m + 1,
                  symbols: const [
                    Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                  ],
                ),
            ],
          ),
      ],
    ),
  );

  (int, int) startAt(int part, int measure) {
    final e = events[PlaybackService.startIndex(
      events,
      partIndex: part,
      measureIndex: measure,
    )];
    return (e.partIndex, e.measureIndex);
  }

  test('playback starts at the selected bar of the selected staff', () {
    expect(startAt(2, 1), (2, 1)); // used to start at staff 1, bar 2
    expect(startAt(1, 0), (1, 0)); // used to start at the very top
    expect(startAt(0, 0), (0, 0));
  });

  test('a bar past the end of a staff starts at the next staff', () {
    expect(startAt(0, 7), (1, 0));
  });
}
