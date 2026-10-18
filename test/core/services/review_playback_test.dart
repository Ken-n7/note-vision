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
  final keys = <int>[];
  @override
  Future<int> loadSoundfontAsset({
    required String assetPath,
    int bank = 0,
    int program = 0,
  }) async => loading == null ? 1 : loading!.future;
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
