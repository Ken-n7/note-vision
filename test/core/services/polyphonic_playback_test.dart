import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/musical_time.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_service.dart';

class _Midi extends MidiPro {
  @override
  Future<void> controlChange({
    required int controller,
    required int value,
    int channel = 0,
    int sfId = 1,
  }) async {}
  final starts = <int>[], stops = <int>[];
  @override
  Future<int> loadSoundfontAsset({
    required String assetPath,
    int bank = 0,
    int program = 0,
  }) async => 1;
  @override
  Future<void> selectInstrument({
    required int sfId,
    int channel = 0,
    int bank = 0,
    int program = 0,
  }) async {}
  @override
  Future<void> playNote({
    int sfId = 1,
    int channel = 0,
    required int key,
    int velocity = 127,
  }) async {
    starts.add(key);
  }

  @override
  Future<void> stopNote({
    int sfId = 1,
    int channel = 0,
    required int key,
  }) async {
    stops.add(key);
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {}
}

Score voices({bool samePitch = false}) => Score(
  id: 'voices',
  title: '',
  composer: '',
  parts: [
    Part(
      id: 'p1',
      name: 'Piano',
      measures: [
        Measure(
          number: 1,
          symbols: [
            const Note(
              step: 'C',
              octave: 4,
              duration: 4,
              type: 'half',
              voice: 1,
            ),
            Note(
              step: samePitch ? 'C' : 'E',
              octave: 4,
              duration: 2,
              type: 'quarter',
              voice: 2,
            ),
            if (!samePitch)
              const Note(
                step: 'G',
                octave: 4,
                duration: 2,
                type: 'quarter',
                voice: 2,
              ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('tempo changes during a held note use the written beat map', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final player = PlaybackService.forTesting(midi);
    addTearDown(player.dispose);
    final score = Score(
      id: 'tempo',
      title: '',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [
            Measure(
              number: 1,
              symbols: const [
                Note(step: 'C', octave: 4, duration: 4, type: 'half'),
              ],
              annotations: [
                const ScoreAnnotation(kind: AnnotationKind.tempo, tempo: 60),
                ScoreAnnotation(
                  kind: AnnotationKind.tempo,
                  tempo: 120,
                  offset: MusicalTime.one,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await player.play(score);
    expect(player.position.durationMs, 1000);
    expect(player.position.measureDurationMs, 1500);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(midi.stops, isEmpty);
    expect(player.position.durationMs, 500);
    await tester.pump(const Duration(milliseconds: 500));
    expect(player.status, PlaybackStatus.stopped);
    expect(midi.stops, [60]);
  });
  testWidgets('review ends at the requested bar with later tempo changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final review = PlaybackService.forTesting(midi);
    addTearDown(review.dispose);
    final score = Score(
      id: 'review-tempo',
      title: '',
      composer: '',
      parts: [
        Part(
          id: 'P1',
          name: 'Voice',
          measures: [
            for (var i = 0; i < 3; i++)
              Measure(
                number: i + 1,
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                ],
                annotations: [
                  ScoreAnnotation(
                    kind: AnnotationKind.tempo,
                    tempo: i == 0 ? 60 : 90,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    await review.play(score, throughMeasureIndex: 0);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(review.status, PlaybackStatus.stopped);
    expect(midi.starts, [60]);
  });

  testWidgets(
    'playback can retry after correcting an unsupported score duration',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi();
      final playback = PlaybackService.forTesting(midi);
      addTearDown(playback.dispose);
      final invalid = voices().replaceSymbolAt(
        0,
        0,
        0,
        const Note(
          step: 'C',
          octave: 4,
          duration: 2,
          type: 'quarter',
          dots: 17,
        ),
      );
      await playback.play(invalid);
      expect(playback.status, PlaybackStatus.error);
      expect(midi.starts, isEmpty);
      await playback.play(voices());
      expect(playback.status, PlaybackStatus.playing);
      expect(midi.starts, [60, 64]);
      playback.stop();
    },
  );
  testWidgets(
    'short voice notes stop independently while a longer note continues',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi();
      final playback = PlaybackService.forTesting(midi);
      addTearDown(playback.dispose);
      await playback.play(voices());
      expect(midi.starts, [60, 64]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, [64]);
      expect(midi.starts, [60, 64, 67]);
      expect(playback.status, PlaybackStatus.playing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, containsAll([60, 64, 67]));
      expect(playback.status, PlaybackStatus.stopped);
    },
  );

  testWidgets(
    'overlapping identical pitches stay held until their last voice ends',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi();
      final playback = PlaybackService.forTesting(midi);
      addTearDown(playback.dispose);
      await playback.play(voices(samePitch: true));
      expect(midi.starts, [60]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, [60]);
    },
  );

  testWidgets('ensemble parts start together and scan rows remain sequential', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final playback = PlaybackService.forTesting(midi);
    addTearDown(playback.dispose);
    final score = Score(
      id: 'parts',
      title: '',
      composer: '',
      playbackLayout: ScorePlaybackLayout.simultaneousParts,
      parts: [
        for (final step in ['C', 'G'])
          Part(
            id: step,
            name: step,
            measures: [
              Measure(
                number: 1,
                symbols: [
                  Note(step: step, octave: 4, duration: 2, type: 'quarter'),
                ],
              ),
            ],
          ),
      ],
    );
    await playback.play(score);
    expect(midi.starts, [60, 67]);
    playback.stop();
    midi.starts.clear();
    await playback.play(
      score.copyWith(playbackLayout: ScorePlaybackLayout.sequentialStaves),
    );
    expect(midi.starts, [60]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(midi.starts, [60, 67]);
    playback.stop();
  });

  testWidgets(
    'pause and resume retain the current polyphonic boundary after pitch edits',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi();
      final playback = PlaybackService.forTesting(midi);
      addTearDown(playback.dispose);
      final score = voices();
      await playback.play(score);
      await tester.pump(const Duration(milliseconds: 500));
      playback.pause();
      final edited = score.replaceSymbolAt(
        0,
        0,
        0,
        const Note(step: 'D', octave: 4, duration: 4, type: 'half', voice: 1),
      );
      midi.starts.clear();
      playback.resume(score: edited);
      expect(midi.starts, [62, 67], reason: 'The ended E4 must not restart');
      await tester.pump(const Duration(milliseconds: 500));
      expect(playback.status, PlaybackStatus.stopped);
    },
  );

  testWidgets('stale waits cannot cut off a new playback run', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final playback = PlaybackService.forTesting(midi);
    addTearDown(playback.dispose);
    await playback.play(voices());
    await tester.pump(const Duration(milliseconds: 250));
    playback.stop();
    midi.stops.clear();
    await playback.play(voices());
    await tester.pump(const Duration(milliseconds: 250));
    expect(midi.stops, isEmpty);
    expect(playback.status, PlaybackStatus.playing);
    playback.stop();
  });
}
