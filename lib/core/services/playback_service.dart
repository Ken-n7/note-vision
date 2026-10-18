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
    this.durationMs = 0,
    this.measureElapsedMs = 0,
    this.measureDurationMs = 0,
    this.nextPartIndex,
    this.nextMeasureIndex,
    this.nextSymbolIndex,
  });

  static const none = PlaybackPosition(
    partIndex: -1,
    measureIndex: -1,
    symbolIndex: -1,
  );

  final int partIndex;
  final int measureIndex;
  final int symbolIndex;
  final int durationMs;
  final int measureElapsedMs;
  final int measureDurationMs;
  final int? nextPartIndex;
  final int? nextMeasureIndex;
  final int? nextSymbolIndex;

  bool get isNone => partIndex < 0;
  bool get hasNext =>
      nextPartIndex != null &&
      nextMeasureIndex != null &&
      nextSymbolIndex != null;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPosition &&
      other.partIndex == partIndex &&
      other.measureIndex == measureIndex &&
      other.symbolIndex == symbolIndex &&
      other.durationMs == durationMs &&
      other.measureElapsedMs == measureElapsedMs &&
      other.measureDurationMs == measureDurationMs &&
      other.nextPartIndex == nextPartIndex &&
      other.nextMeasureIndex == nextMeasureIndex &&
      other.nextSymbolIndex == nextSymbolIndex;

  @override
  int get hashCode => Object.hash(
    partIndex,
    measureIndex,
    symbolIndex,
    durationMs,
    measureElapsedMs,
    measureDurationMs,
    nextPartIndex,
    nextMeasureIndex,
    nextSymbolIndex,
  );
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
/// PlaybackService.instance.stop();       // on screen dispose
/// PlaybackService.instance.setTempo(90);
/// ```
///
/// [dispose] closes the streams of this app-wide instance; only tests call
/// it. Screens call [stop] when they close.
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
  PlaybackService._({MidiPro? midi}) : _midi = midi ?? MidiPro();

  @visibleForTesting
  factory PlaybackService.forTesting(MidiPro midi) =>
      PlaybackService._(midi: midi);

  static final PlaybackService instance = PlaybackService._();

  // ── MIDI constants ─────────────────────────────────────────────────────
  static const String _soundfontAsset = 'assets/soundfonts/piano.sf2';
  static const int _midiChannel = 0;
  static const int _bank = 0;
  static const int _program = 0; // acoustic grand piano
  static const int _velocity = 90;

  // ── Dependencies ────────────────────────────────────────────────────────
  final MidiPro _midi;
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

  /// Counts playback loops. A loop that wakes up after a newer one started
  /// (play() while playing, as when seeking) must leave the notes and the
  /// state to the newer loop.
  int _loopRun = 0;
  int _playRequest = 0;
  final List<int> _activeMidiNotes = <int>[];

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

  @visibleForTesting
  void emitPositionForTesting(PlaybackPosition position) {
    _positionController.add(position);
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
        error:
            'Could not load soundfont. '
            'Add assets/soundfonts/piano.sf2 (any standard GM SF2 file) '
            'then run: flutter pub get\n\nDetail: $e',
      );
    } finally {
      _initFuture = null;
    }
  }

  // ── Playback control ───────────────────────────────────────────────────

  /// Index of the first event at or after measure [measureIndex] of part
  /// [partIndex]. Events run part by part, so earlier parts are skipped.
  static int startIndex(
    List<PlaybackEvent> events, {
    required int partIndex,
    required int measureIndex,
  }) {
    final i = events.indexWhere(
      (e) =>
          e.partIndex > partIndex ||
          (e.partIndex == partIndex && e.measureIndex >= measureIndex),
    );
    return i < 0 ? 0 : i;
  }

  /// Starts playback from measure [fromMeasureIndex] of part [fromPartIndex]
  /// (default: the beginning), then carries on through the later parts.
  /// Safe to call while already playing (stops previous playback first).
  Future<void> play(
    Score score, {
    int fromMeasureIndex = 0,
    int fromPartIndex = 0,
    int? throughMeasureIndex,
  }) async {
    if (_status == PlaybackStatus.playing || _status == PlaybackStatus.paused) {
      stop();
    }
    final request = ++_playRequest;
    if (!_initialized) await init();
    if (request != _playRequest || _status == PlaybackStatus.error) return;

    _events = _converter.buildEvents(score);
    if (throughMeasureIndex != null) {
      _events = _events
          .where(
            (event) =>
                event.partIndex == fromPartIndex &&
                event.measureIndex >= fromMeasureIndex &&
                event.measureIndex <= throughMeasureIndex,
          )
          .toList();
    }
    if (_events.isEmpty) return;

    _currentEventIndex = startIndex(
      _events,
      partIndex: fromPartIndex,
      measureIndex: fromMeasureIndex,
    );

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
    _playRequest++;
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
    final run = ++_loopRun;
    while (_shouldPlay && _currentEventIndex < _events.length) {
      final event = _events[_currentEventIndex];
      final groupEnd = _eventGroupEnd(_currentEventIndex);
      final nextEvent = groupEnd < _events.length ? _events[groupEnd] : null;
      final ms = _converter.scaledDuration(event.baseDurationMs, _tempo);
      final measureElapsedMs = _converter.scaledDuration(
        _measureElapsedBaseDuration(_currentEventIndex),
        _tempo,
      );
      final measureDurationMs = _converter.scaledDuration(
        _measureBaseDuration(_currentEventIndex),
        _tempo,
      );

      // Emit current score position for the viewer highlight.
      _positionController.add(
        PlaybackPosition(
          partIndex: event.partIndex,
          measureIndex: event.measureIndex,
          symbolIndex: event.symbolIndex,
          durationMs: ms,
          measureElapsedMs: measureElapsedMs,
          measureDurationMs: measureDurationMs,
          nextPartIndex: nextEvent?.partIndex,
          nextMeasureIndex: nextEvent?.measureIndex,
          nextSymbolIndex: nextEvent?.symbolIndex,
        ),
      );

      _activeMidiNotes.clear();

      // Fire all notes in the current rhythmic group without awaiting.
      // Awaiting playNote() blocks for ~10–20 ms per call (MIDI platform
      // overhead), which would delay _waitMs() and make the visual clock
      // run ahead of the audio by that amount on every note boundary.
      // Fire-and-forget keeps the wall-clock timer aligned with the audio.
      if (_sfId != null) {
        for (var i = _currentEventIndex; i < groupEnd; i++) {
          final groupedEvent = _events[i];
          if (groupedEvent.isRest) continue;
          unawaited(
            _midi.playNote(
              sfId: _sfId!,
              channel: _midiChannel,
              key: groupedEvent.midiNote,
              velocity: _velocity,
            ),
          );
          _activeMidiNotes.add(groupedEvent.midiNote);
        }
      }

      // Wait for duration, scaled to current tempo.
      final completed = await _waitMs(ms);
      if (run != _loopRun) return; // a newer loop owns playback now

      // Stop notes without awaiting — same reason as playNote above.
      // _stopActiveNotes() copies _activeMidiNotes before clearing it so the
      // next group can safely populate the list while stops are in flight.
      unawaited(_stopActiveNotes());

      if (!completed) break; // paused or stopped mid-note
      _currentEventIndex = groupEnd;
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
    unawaited(_stopActiveNotes());
  }

  int _eventGroupEnd(int startIndex) {
    var index = startIndex + 1;
    while (index < _events.length && _events[index].isChordTone) {
      index++;
    }
    return index;
  }

  int _measureElapsedBaseDuration(int eventIndex) {
    final current = _events[eventIndex];
    var elapsed = 0;
    for (var i = 0; i < eventIndex; i++) {
      final event = _events[i];
      if (event.partIndex != current.partIndex ||
          event.measureIndex != current.measureIndex) {
        continue;
      }
      if (!event.isChordTone) elapsed += event.baseDurationMs;
    }
    return elapsed;
  }

  int _measureBaseDuration(int eventIndex) {
    final current = _events[eventIndex];
    var duration = 0;
    for (final event in _events) {
      if (event.partIndex != current.partIndex ||
          event.measureIndex != current.measureIndex) {
        continue;
      }
      if (!event.isChordTone) duration += event.baseDurationMs;
    }
    return duration > 0 ? duration : current.baseDurationMs;
  }

  Future<void> _stopActiveNotes() async {
    if (_sfId == null || _activeMidiNotes.isEmpty) return;
    final keys = List<int>.from(_activeMidiNotes);
    _activeMidiNotes.clear();
    for (final key in keys) {
      await _midi.stopNote(sfId: _sfId!, channel: _midiChannel, key: key);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _emitState(PlaybackStatus status, {String? error}) {
    _status = status;
    _stateController.add(PlaybackState(status: status, error: error));
  }
}
