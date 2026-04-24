import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/score.dart';
import 'playback_converter.dart';
import 'usage_stats_service.dart';

export 'playback_converter.dart' show PlaybackEvent, PlaybackConverter;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

enum PlaybackStatus { stopped, playing, paused, error }

class PlaybackState {
  const PlaybackState({required this.status, this.error});

  final PlaybackStatus status;

  /// Non-null only when [status] == [PlaybackStatus.error].
  final String? error;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isStopped => status == PlaybackStatus.stopped;

  @override
  String toString() => 'PlaybackState(status: $status, error: $error)';
}

/// The score position currently being played.
/// [partIndex] == -1 means "no active position" (cleared on stop/finish).
class PlaybackPosition {
  const PlaybackPosition({
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
  });

  static const none = PlaybackPosition(partIndex: -1, measureIndex: -1, symbolIndex: -1);

  final int partIndex;
  final int measureIndex;
  final int symbolIndex;

  bool get isNone => partIndex < 0;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPosition &&
      other.partIndex == partIndex &&
      other.measureIndex == measureIndex &&
      other.symbolIndex == symbolIndex;

  @override
  int get hashCode => Object.hash(partIndex, measureIndex, symbolIndex);
}

// ---------------------------------------------------------------------------
// PlaybackService
// ---------------------------------------------------------------------------

/// Singleton service that synthesises a [Score] to MIDI audio via
/// flutter_midi_pro (FluidSynth on Android, AVFoundation on iOS/macOS).
///
/// Score → event conversion is handled by [PlaybackConverter] (pure Dart,
/// unit-testable without this class).
///
/// Usage
/// -----
/// ```dart
/// await PlaybackService.instance.init();  // once per screen
/// await PlaybackService.instance.play(score);
/// PlaybackService.instance.pause();
/// PlaybackService.instance.resume();
/// PlaybackService.instance.stop();
/// PlaybackService.instance.setTempo(90);
/// PlaybackService.instance.dispose();    // on screen dispose
/// ```
///
/// Soundfont requirement
/// ---------------------
/// Place any standard GM piano SF2 file at:
///   assets/soundfonts/piano.sf2
///
/// Free options (1–7 MB):
///   • TimGM6mb.sf2          – from MuseScore / Timidity++ project
///   • GeneralUser GS v1.471.sf2  – schristiancollins.com
class PlaybackService {
  PlaybackService._();

  static final PlaybackService instance = PlaybackService._();

  // ── MIDI constants ─────────────────────────────────────────────────────
  static const String _soundfontAsset = 'assets/soundfonts/piano.sf2';
  static const int _midiChannel = 0;
  static const int _bank = 0;
  static const int _program = 0; // acoustic grand piano
  static const int _velocity = 90;

  // ── Dependencies ────────────────────────────────────────────────────────
  final MidiPro _midi = MidiPro();
  final _converter = const PlaybackConverter();
  int? _sfId;
  bool _initialized = false;

  /// Guards against concurrent [init] calls (e.g. from [_initPlayback] in
  /// initState and an immediate [play] tap before the soundfont has loaded).
  Future<void>? _initFuture;

  // ── Runtime state ───────────────────────────────────────────────────────
  int _tempo = PlaybackConverter.defaultTempo;
  PlaybackStatus _status = PlaybackStatus.stopped;

  bool _shouldPlay = false;
  Timer? _noteTimer;
  Completer<bool>? _waitCompleter;

  List<PlaybackEvent> _events = const [];
  int _currentEventIndex = 0;

  // ── Streams ────────────────────────────────────────────────────────────
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<PlaybackPosition>.broadcast();

  Stream<PlaybackState> get stateStream => _stateController.stream;
  Stream<PlaybackPosition> get positionStream => _positionController.stream;

  PlaybackStatus get status => _status;
  int get tempo => _tempo;

  // Emit a state directly — used only in tests to simulate playback transitions.
  @visibleForTesting
  void emitStateForTesting(PlaybackState state) {
    _status = state.status;
    _stateController.add(state);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Loads the soundfont asset. Safe to call multiple times — no-ops once
  /// initialized. Concurrent calls await the same in-flight load rather than
  /// starting a second one. Must be called before [play].
  Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = _loadSoundfont();
    await _initFuture;
  }

  Future<void> _loadSoundfont() async {
    try {
      _sfId = await _midi.loadSoundfontAsset(
        assetPath: _soundfontAsset,
        bank: _bank,
        program: _program,
      );
      await _midi.selectInstrument(
        sfId: _sfId!,
        channel: _midiChannel,
        bank: _bank,
        program: _program,
      );
      _initialized = true;
    } catch (e) {
      _initialized = false;
      _sfId = null;
      _emitState(
        PlaybackStatus.error,
        error: 'Could not load soundfont. '
            'Add assets/soundfonts/piano.sf2 (any standard GM SF2 file) '
            'then run: flutter pub get\n\nDetail: $e',
      );
    } finally {
      _initFuture = null;
    }
  }

  // ── Playback control ───────────────────────────────────────────────────

  /// Starts playback from the beginning. Safe to call while already playing
  /// (stops previous playback first).
  Future<void> play(Score score) async {
    if (_status == PlaybackStatus.playing) stop();
    if (!_initialized) await init();
    if (_status == PlaybackStatus.error) return;

    _events = _converter.buildEvents(score);
    if (_events.isEmpty) return;

    _currentEventIndex = 0;
    _shouldPlay = true;
    _emitState(PlaybackStatus.playing);
    unawaited(UsageStatsService.incrementPlaybacks());
    _runLoop();
  }

  void pause() {
    if (_status != PlaybackStatus.playing) return;
    _shouldPlay = false;
    _interruptWait();
    _stopCurrentNote();
    _emitState(PlaybackStatus.paused);
  }

  void resume() {
    if (_status != PlaybackStatus.paused) return;
    _shouldPlay = true;
    _emitState(PlaybackStatus.playing);
    _runLoop();
  }

  void stop() {
    if (_status == PlaybackStatus.stopped) return;
    _shouldPlay = false;
    _interruptWait();
    _stopCurrentNote();
    _currentEventIndex = 0;
    _emitState(PlaybackStatus.stopped);
    _positionController.add(PlaybackPosition.none);
  }

  /// Updates playback tempo in BPM. Takes effect on the next note boundary.
  void setTempo(int bpm) {
    _tempo = bpm.clamp(20, 300);
  }

  Future<void> dispose() async {
    stop();
    if (_sfId != null) {
      await _midi.unloadSoundfont(_sfId!);
      _sfId = null;
    }
    _initialized = false;
    if (!_stateController.isClosed) _stateController.close();
    if (!_positionController.isClosed) _positionController.close();
  }

  // ── Internal playback loop ─────────────────────────────────────────────

  void _runLoop() async {
    while (_shouldPlay && _currentEventIndex < _events.length) {
      final event = _events[_currentEventIndex];

      // Emit current score position for the viewer highlight.
      _positionController.add(PlaybackPosition(
        partIndex: event.partIndex,
        measureIndex: event.measureIndex,
        symbolIndex: event.symbolIndex,
      ));

      // Play MIDI note (skip for rests).
      if (!event.isRest && _sfId != null) {
        await _midi.playNote(
          sfId: _sfId!,
          channel: _midiChannel,
          key: event.midiNote,
          velocity: _velocity,
        );
      }

      // Wait for duration, scaled to current tempo.
      final ms = _converter.scaledDuration(event.baseDurationMs, _tempo);
      final completed = await _waitMs(ms);

      // Stop note before advancing.
      if (!event.isRest && _sfId != null) {
        await _midi.stopNote(
          sfId: _sfId!,
          channel: _midiChannel,
          key: event.midiNote,
        );
      }

      if (!completed) break; // paused or stopped mid-note
      _currentEventIndex++;
    }

    // Natural end — reset to stopped.
    if (_shouldPlay) {
      _shouldPlay = false;
      _currentEventIndex = 0;
      _emitState(PlaybackStatus.stopped);
      _positionController.add(PlaybackPosition.none);
    }
  }

  // ── Timer helpers ──────────────────────────────────────────────────────

  Future<bool> _waitMs(int ms) {
    // If stop() was called while we were inside await _midi.playNote() (before
    // this wait started), bail out immediately instead of starting a new timer.
    if (!_shouldPlay) return Future.value(false);
    final completer = Completer<bool>();
    _waitCompleter = completer;
    _noteTimer = Timer(Duration(milliseconds: ms.clamp(10, 60000)), () {
      if (!completer.isCompleted) completer.complete(true);
    });
    return completer.future;
  }

  void _interruptWait() {
    _noteTimer?.cancel();
    _noteTimer = null;
    if (_waitCompleter != null && !_waitCompleter!.isCompleted) {
      _waitCompleter!.complete(false);
    }
    _waitCompleter = null;
  }

  void _stopCurrentNote() {
    if (_sfId == null || _currentEventIndex >= _events.length) return;
    final event = _events[_currentEventIndex];
    if (!event.isRest) {
      _midi.stopNote(
        sfId: _sfId!,
        channel: _midiChannel,
        key: event.midiNote,
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _emitState(PlaybackStatus status, {String? error}) {
    _status = status;
    _stateController.add(PlaybackState(status: status, error: error));
  }
}
