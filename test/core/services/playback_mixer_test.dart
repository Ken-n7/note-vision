import 'dart:async';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note_vision/core/models/part_playback.dart';
import 'package:note_vision/core/services/playback_service.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import '../../support/playback_mix_fixture.dart';

class Midi extends MidiPro {
  final programs = <(int, int)>[],
      controls = <(int, int, int)>[],
      starts = <(int, int, int)>[],
      stops = <(int, int)>[];
  Completer<void>? selecting;
  bool fail = false;
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
  }) async {
    programs.add((channel, program));
    if (fail) throw StateError('unavailable');
    if (selecting != null) await selecting!.future;
  }

  @override
  Future<void> controlChange({
    required int controller,
    required int value,
    int sfId = 1,
    int channel = 0,
  }) async {
    controls.add((channel, controller, value));
  }

  @override
  Future<void> playNote({
    int sfId = 1,
    int channel = 0,
    required int key,
    int velocity = 127,
  }) async {
    starts.add((channel, key, velocity));
  }

  @override
  Future<void> stopNote({
    int sfId = 1,
    int channel = 0,
    required int key,
  }) async {
    stops.add((channel, key));
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'equal pitches on separate instruments start and stop independently',
    (tester) async {
      final midi = Midi();
      final player = PlaybackService.forTesting(midi);
      addTearDown(player.dispose);
      final score = EditorState(score: ensemble()).setPlaybackMix([
        const PartPlayback(program: 73, volume: 50, pan: -90),
        const PartPlayback(program: 40, pan: 90),
      ]).score;
      await player.play(score);
      expect(midi.programs, containsAll([(0, 73), (1, 40)]));
      expect(
        midi.controls,
        containsAll([(0, 7, 64), (0, 10, 0), (1, 7, 127), (1, 10, 127)]),
      );
      expect(midi.starts.map((n) => (n.$1, n.$2)), [(0, 60), (1, 60)]);
      player.pause();
      expect(midi.stops, containsAll([(0, 60), (1, 60)]));
      midi.stops.clear();
      player.resume();
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, containsAll([(0, 60), (1, 60)]));
    },
  );
  testWidgets(
    'mute and solo affect sound without changing duration or highlights',
    (tester) async {
      final midi = Midi();
      final player = PlaybackService.forTesting(midi);
      addTearDown(player.dispose);
      var score = EditorState(score: ensemble()).setPlaybackMix([
        const PartPlayback(mute: true),
        const PartPlayback(program: 40, solo: true),
      ]).score;
      await player.play(score);
      expect(midi.starts, hasLength(1));
      expect(player.position.partIndex, 0);
      player.stop();
      midi.starts.clear();
      score = EditorState(score: score).setPlaybackMix([
        const PartPlayback(mute: true),
        const PartPlayback(mute: true),
      ]).score;
      await player.play(score);
      expect(midi.starts, isEmpty);
      expect(player.status, PlaybackStatus.playing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.status, PlaybackStatus.stopped);
    },
  );
  testWidgets(
    'linked piano staves share a channel and overlapping pitch count',
    (tester) async {
      final midi = Midi();
      final player = PlaybackService.forTesting(midi);
      addTearDown(player.dispose);
      await player.play(ensemble(linked: true));
      expect(midi.starts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(midi.stops, [(0, 60)]);
    },
  );
  testWidgets(
    'mix changed during pause configures before resume; next score resets controls',
    (tester) async {
      final midi = Midi();
      final player = PlaybackService.forTesting(midi);
      addTearDown(player.dispose);
      final score = ensemble();
      await player.play(score);
      player.pause();
      midi.starts.clear();
      final edited = EditorState(score: score).setPlaybackMix([
        const PartPlayback(program: 73, volume: 20, pan: -90),
        const PartPlayback(mute: true),
      ]).score;
      player.resume(score: edited);
      await tester.pump();
      expect(midi.programs.last, (0, 73));
      expect(midi.controls, contains((0, 7, 25)));
      expect(midi.starts, hasLength(1));
      player.stop();
      midi.controls.clear();
      await player.play(score);
      expect(midi.controls, containsAll([(0, 7, 127), (0, 10, 64)]));
      player.stop();
    },
  );
  testWidgets('Stop during delayed instrument selection cancels all attacks', (
    tester,
  ) async {
    final midi = Midi();
    final player = PlaybackService.forTesting(midi);
    addTearDown(player.dispose);
    await player.init();
    midi.selecting = Completer<void>();
    final pending = player.play(ensemble());
    await tester.pump();
    player.stop();
    midi.selecting!.complete();
    await pending;
    await tester.pump();
    expect(midi.starts, isEmpty);
    expect(player.status, PlaybackStatus.stopped);
  });
  testWidgets(
    'configuration error can retry; excess instruments report a useful error',
    (tester) async {
      final midi = Midi();
      final player = PlaybackService.forTesting(midi);
      addTearDown(player.dispose);
      await player.init();
      midi.fail = true;
      await player.play(ensemble());
      expect(player.status, PlaybackStatus.error);
      expect(midi.starts, isEmpty);
      midi.fail = false;
      await player.play(ensemble());
      expect(player.status, PlaybackStatus.playing);
      player.stop();
      midi.starts.clear();
      final states = <PlaybackState>[];
      final sub = player.stateStream.listen(states.add);
      addTearDown(sub.cancel);
      await player.play(ensemble(count: 16));
      await tester.pump();
      expect(player.status, PlaybackStatus.error);
      expect(states.last.error, contains('15 sounding instruments'));
      expect(midi.starts, isEmpty);
    },
  );
}
