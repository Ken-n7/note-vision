import 'dart:async';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Midi extends MidiPro {
  Completer<int>? loading;
  bool failLoad = false;
  final keys = <int>[];
  @override
  Future<int> loadSoundfontAsset({
    required String assetPath,
    int bank = 0,
    int program = 0,
  }) async {
    if (failLoad) throw StateError('Soundfont unavailable');
    return loading == null ? 1 : loading!.future;
  }

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
    keys.add(key);
  }

  @override
  Future<void> stopNote({
    int sfId = 1,
    int channel = 0,
    required int key,
  }) async {}
  @override
  Future<void> unloadSoundfont(int sfId) async {}
}

Score _score() => Score(
  id: 'passage',
  title: '',
  composer: '',
  parts: [
    for (var p = 0; p < 2; p++)
      Part(
        id: 'p$p',
        name: 'Staff $p',
        measures: [
          for (var m = 0; m < 4; m++)
            Measure(
              number: m + 1,
              symbols: [
                Note(
                  step: ['C', 'D', 'E', 'F'][m],
                  octave: p + 4,
                  duration: 1,
                  type: 'sixteenth',
                ),
              ],
            ),
        ],
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeking cues silently and resume starts at the cued measure', () async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final playback = PlaybackService.forTesting(midi);
    await playback.seek(_score(), fromPartIndex: 1, fromMeasureIndex: 1);
    expect(playback.status, PlaybackStatus.stopped);
    expect(playback.position.partIndex, 1);
    expect(playback.position.measureIndex, 1);
    expect(midi.keys, isEmpty);
    playback.stop();
    expect(playback.position.isNone, isTrue);

    await playback.play(_score());
    playback.pause();
    final heard = midi.keys.length;
    await playback.seek(_score(), fromPartIndex: 1, fromMeasureIndex: 1);
    expect(playback.status, PlaybackStatus.paused);
    expect(midi.keys, hasLength(heard));
    playback.resume();
    expect(midi.keys.last, 74);
    await playback.dispose();
  });

  test('resume uses note edits made while paused', () async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi();
    final playback = PlaybackService.forTesting(midi);
    final original = _score();
    await playback.play(original);
    playback.pause();
    final edited = original.replaceSymbolAt(
      0,
      0,
      0,
      const Note(step: 'G', octave: 4, duration: 1, type: 'sixteenth'),
    );
    playback.resume(score: edited);
    expect(midi.keys, [60, 67]);
    await playback.dispose();
  });

  test('playback can retry after a soundfont-loading failure', () async {
    SharedPreferences.setMockInitialValues({});
    final midi = _Midi()..failLoad = true;
    final playback = PlaybackService.forTesting(midi);
    await playback.play(_score());
    expect(playback.status, PlaybackStatus.error);
    expect(midi.keys, isEmpty);
    midi.failLoad = false;
    await playback.play(_score());
    expect(playback.status, PlaybackStatus.playing);
    expect(midi.keys, [60]);
    await playback.dispose();
  });
  test(
    'audition stops at the requested measure and keeps original score positions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi();
      final playback = PlaybackService.forTesting(midi)..setTempo(300);
      final positions = <PlaybackPosition>[];
      final sub = playback.positionStream.listen(positions.add);
      final stopped = playback.stateStream.firstWhere(
        (s) => s.status == PlaybackStatus.stopped,
      );
      await playback.play(
        _score(),
        fromPartIndex: 1,
        fromMeasureIndex: 1,
        throughMeasureIndex: 2,
      );
      await stopped.timeout(const Duration(seconds: 3));
      final heard = positions.where((p) => !p.isNone).toList();
      expect(heard.map((p) => (p.partIndex, p.measureIndex)), [(1, 1), (1, 2)]);
      expect(midi.keys, [74, 76]);
      expect(playback.status, PlaybackStatus.stopped);
      await sub.cancel();
      await playback.dispose();
    },
  );

  test(
    'closing review while the soundfont loads cancels deferred playback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final midi = _Midi()..loading = Completer<int>();
      final playback = PlaybackService.forTesting(midi);
      final playing = playback.play(_score(), throughMeasureIndex: 1);
      await Future<void>.delayed(Duration.zero);
      playback.stop();
      midi.loading!.complete(1);
      await playing;
      expect(midi.keys, isEmpty);
      expect(playback.status, PlaybackStatus.stopped);
      await playback.dispose();
    },
  );
}
