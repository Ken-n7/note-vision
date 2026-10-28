import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/score.dart';
import 'playback_converter.dart';
import 'playback_schedule.dart';
import 'score_timeline.dart';
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
  Score? _playingScore;
  PlaybackPosition _position = PlaybackPosition.none;
  int _currentEventIndex = 0;
  PlaybackPlan? _plan;
  PlaybackSchedule? _schedule;
  int _frameIndex = 0;
  int _focusPart = 0;
  int? _throughMeasure;
  int _reviewFirstMeasure = 0;
  int _reviewPart = 0;

  /// Counts playback loops. A loop that wakes up after a newer one started
  /// (play() while playing, as when seeking) must leave the notes and the
  /// state to the newer loop.
  int _loopRun = 0;
  int _playRequest = 0;
  final Map<int, int> _activeMidiNotes = <int, int>{};

  // ── Streams ────────────────────────────────────────────────────────────
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<PlaybackPosition>.broadcast();

  Stream<PlaybackState> get stateStream => _stateController.stream;
  Stream<PlaybackPosition> get positionStream => _positionController.stream;

  PlaybackStatus get status => _status;
  int get tempo => _tempo;
  PlaybackPosition get position => _position;

  // Emit a state directly — used only in tests to simulate playback transitions.
  @visibleForTesting
  void emitStateForTesting(PlaybackState state) {
    _status = state.status;
    _stateController.add(state);
  }

  @visibleForTesting
  void emitPositionForTesting(PlaybackPosition position) {
    _emitPosition(position);
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
      if (_status == PlaybackStatus.error) _emitState(PlaybackStatus.stopped);
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
  /// (default: the beginning), following the score's ensemble or staff layout.
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
    if (request != _playRequest || !_initialized) return;
    if (_status == PlaybackStatus.error) _emitState(PlaybackStatus.stopped);

    _throughMeasure = throughMeasureIndex;
    _reviewFirstMeasure = fromMeasureIndex;
    _reviewPart = fromPartIndex;
    _focusPart = fromPartIndex;
    if (!_prepareScore(score)) return;
    _cue(fromPartIndex, fromMeasureIndex);

    _shouldPlay = true;
    _emitState(PlaybackStatus.playing);
    unawaited(UsageStatsService.incrementPlaybacks());
    _runLoop();
  }

  void pause() {
    if (_status != PlaybackStatus.playing) return;
    _loopRun++;
    _shouldPlay = false;
    _interruptWait();
    _stopCurrentNote();
    _emitState(PlaybackStatus.paused);
  }

  /// Cue a measure without starting audio when stopped or paused.
  Future<void> seek(
    Score score, {
    int fromMeasureIndex = 0,
    int fromPartIndex = 0,
  }) async {
    if (_status == PlaybackStatus.playing) {
      await play(
        score,
        fromMeasureIndex: fromMeasureIndex,
        fromPartIndex: fromPartIndex,
      );
      return;
    }
    _playRequest++;
    _loopRun++;
    _throughMeasure = null;
    _focusPart = fromPartIndex;
    if (!_prepareScore(score)) return;
    _cue(fromPartIndex, fromMeasureIndex);
    _emitPosition(_positionAt(_frameIndex));
  }

  void resume({Score? score}) {
    if (_status != PlaybackStatus.paused) return;
    if (score != null && _currentEventIndex < _events.length) {
      final previous = _events[_currentEventIndex];
      final elapsed =
          _schedule!.frames[_frameIndex].timeMs - previous.baseOnsetMs;
      final id = _playingScore
          ?.getSymbolAt(
            previous.partIndex,
            previous.measureIndex,
            previous.symbolIndex,
          )
          ?.toJson()['reviewId'];
      if (!_prepareScore(score)) return;
      var index = id == null
          ? -1
          : _events.indexWhere(
              (event) =>
                  score
                      .getSymbolAt(
                        event.partIndex,
                        event.measureIndex,
                        event.symbolIndex,
                      )
                      ?.toJson()['reviewId'] ==
                  id,
            );
      if (index < 0) {
        index = _events.indexWhere(
          (event) =>
              event.partIndex == previous.partIndex &&
              (event.measureIndex > previous.measureIndex ||
                  event.measureIndex == previous.measureIndex &&
                      event.symbolIndex >= previous.symbolIndex),
        );
      }
      if (index < 0) {
        stop();
        return;
      }
      _currentEventIndex = index;
      final phase = _events[index].baseOnsetMs + elapsed;
      final phaseIndex = _schedule!.frames.indexWhere((f) => f.timeMs == phase);
      _frameIndex = phaseIndex >= 0 && phase < _events[index].baseEndMs
          ? phaseIndex
          : _schedule!.frameAt(_events[index].baseOnsetMs);
    }
    _shouldPlay = true;
    _emitState(PlaybackStatus.playing);
    _runLoop();
  }

  bool _prepareScore(Score score) {
    try {
      final plan = _converter.buildPlan(score);
      _events = _throughMeasure == null
          ? plan.events
          : plan.events
                .where(
                  (event) =>
                      event.partIndex == _reviewPart &&
                      event.measureIndex >= _reviewFirstMeasure &&
                      event.measureIndex <= _throughMeasure!,
                )
                .toList();
      if (_events.isEmpty) {
        stop();
        return false;
      }
      final measures = plan.timeline.measures.where(
        (measure) =>
            _throughMeasure == null ||
            measure.partIndex == _reviewPart &&
                measure.measureIndex >= _reviewFirstMeasure &&
                measure.measureIndex <= _throughMeasure!,
      );
      final boundaries = [
        for (final measure in measures) ...[
          PlaybackConverter.baseMilliseconds(measure.onset),
          PlaybackConverter.baseMilliseconds(measure.onset + measure.duration),
        ],
      ];
      final end = boundaries.fold(0, (last, time) => time > last ? time : last);
      _schedule = PlaybackSchedule(_events, endMs: end, boundaries: boundaries);
      _plan = plan;
      _playingScore = score;
      return true;
    } on ScoreTimelineException catch (error) {
      stop();
      _emitState(PlaybackStatus.error, error: error.message);
      return false;
    } on FormatException {
      stop();
      _emitState(
        PlaybackStatus.error,
        error: 'This score has timing that cannot be played yet.',
      );
      return false;
    }
  }

  void _cue(int part, int measure) {
    final simultaneous =
        _playingScore!.playbackLayout == ScorePlaybackLayout.simultaneousParts;
    final target = _plan!.timeline.measures
        .where(
          (m) => simultaneous
              ? m.measureIndex >= measure
              : m.partIndex > part ||
                    m.partIndex == part && m.measureIndex >= measure,
        )
        .firstOrNull;
    final time = target == null
        ? 0
        : PlaybackConverter.baseMilliseconds(target.onset);
    _frameIndex = _schedule!.frameAt(time);
    _currentEventIndex = _schedule!.primaryAt(time, _focusPart) ?? 0;
  }

  void stop() {
    _playRequest++;
    _loopRun++;
    _shouldPlay = false;
    _interruptWait();
    _stopCurrentNote();
    if (_status == PlaybackStatus.stopped && _position.isNone) return;
    _currentEventIndex = 0;
    _emitState(PlaybackStatus.stopped);
    _emitPosition(PlaybackPosition.none);
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
    final schedule = _schedule;
    if (schedule == null) return;
    var restarting = true;
    while (_shouldPlay && _frameIndex < schedule.frames.length) {
      final frame = schedule.frames[_frameIndex];
      if (!restarting) {
        for (final i in frame.stops) {
          _releaseNote(_events[i]);
        }
      }
      final starts = restarting
          ? schedule.activeAt(frame.timeMs)
          : frame.starts;
      for (final i in starts) {
        _startNote(_events[i], run);
      }
      restarting = false;
      if (_frameIndex + 1 >= schedule.frames.length) break;
      _currentEventIndex =
          schedule.primaryAt(frame.timeMs, _focusPart) ?? _currentEventIndex;
      _emitPosition(_positionAt(_frameIndex));
      final next = schedule.frames[_frameIndex + 1];
      final ms = _converter.scaledDuration(next.timeMs - frame.timeMs, _tempo);
      final completed = await _waitMs(ms);
      if (run != _loopRun) return;
      if (!completed) return;
      _frameIndex++;
    }
    if (_shouldPlay && run == _loopRun) {
      _shouldPlay = false;
      _stopCurrentNote();
      _currentEventIndex = 0;
      _frameIndex = 0;
      _emitState(PlaybackStatus.stopped);
      _emitPosition(PlaybackPosition.none);
    }
  }

  void _startNote(PlaybackEvent event, int run) {
    if (event.isRest || _sfId == null) return;
    final count = _activeMidiNotes[event.midiNote] ?? 0;
    _activeMidiNotes[event.midiNote] = count + 1;
    if (count > 0) return;
    unawaited(
      _midi
          .playNote(
            sfId: _sfId!,
            channel: _midiChannel,
            key: event.midiNote,
            velocity: _velocity,
          )
          .catchError((Object error) {
            if (run == _loopRun && _shouldPlay) {
              stop();
              _emitState(
                PlaybackStatus.error,
                error: 'Audio playback failed. Try again.',
              );
            }
          }),
    );
  }

  void _releaseNote(PlaybackEvent event) {
    if (event.isRest || _sfId == null) return;
    final count = _activeMidiNotes[event.midiNote];
    if (count == null) return;
    if (count > 1) {
      _activeMidiNotes[event.midiNote] = count - 1;
      return;
    }
    _activeMidiNotes.remove(event.midiNote);
    unawaited(
      _midi.stopNote(sfId: _sfId!, channel: _midiChannel, key: event.midiNote),
    );
  }

  void _emitPosition(PlaybackPosition position) {
    _position = position;
    _positionController.add(position);
  }

  PlaybackPosition _positionAt(int frameIndex) {
    final schedule = _schedule!;
    final time = schedule.frames[frameIndex].timeMs;
    final index = schedule.primaryAt(time, _focusPart) ?? _currentEventIndex;
    final event = _events[index];
    final measure = _plan!.timeline.measures
        .where(
          (m) =>
              m.partIndex == _focusPart &&
              PlaybackConverter.baseMilliseconds(m.onset) <= time &&
              PlaybackConverter.baseMilliseconds(m.onset + m.duration) > time,
        )
        .firstOrNull;
    final nextTime = frameIndex + 1 < schedule.frames.length
        ? schedule.frames[frameIndex + 1].timeMs
        : time;
    final nextIndex = schedule.primaryAt(nextTime, _focusPart);
    final next = nextIndex == null ? null : _events[nextIndex];
    final measureStart = measure == null
        ? event.baseMeasureOnsetMs
        : PlaybackConverter.baseMilliseconds(measure.onset);
    final measureDuration = measure == null
        ? event.baseMeasureDurationMs
        : PlaybackConverter.baseMilliseconds(measure.onset + measure.duration) -
              measureStart;
    return PlaybackPosition(
      partIndex: measure?.partIndex ?? event.partIndex,
      measureIndex: measure?.measureIndex ?? event.measureIndex,
      symbolIndex:
          measure != null &&
              (measure.measureIndex != event.measureIndex ||
                  measure.partIndex != event.partIndex)
          ? -1
          : event.symbolIndex,
      durationMs: _converter.scaledDuration(nextTime - time, _tempo),
      measureElapsedMs: _converter.scaledDuration(time - measureStart, _tempo),
      measureDurationMs: _converter.scaledDuration(measureDuration, _tempo),
      nextPartIndex: next?.partIndex,
      nextMeasureIndex: next?.measureIndex,
      nextSymbolIndex: next?.symbolIndex,
    );
  }

  // ── Timer helpers ──────────────────────────────────────────────────────

  Future<bool> _waitMs(int ms) {
    // If stop() was called while we were inside await _midi.playNote() (before
    // this wait started), bail out immediately instead of starting a new timer.
    if (!_shouldPlay) return Future.value(false);
    final completer = Completer<bool>();
    _waitCompleter = completer;
    _noteTimer = Timer(Duration(milliseconds: ms.clamp(1, 60000)), () {
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

  Future<void> _stopActiveNotes() async {
    if (_sfId == null || _activeMidiNotes.isEmpty) return;
    final keys = List<int>.from(_activeMidiNotes.keys);
    _activeMidiNotes.clear();
    // Queue every stop before a subsequent play/resume can queue new attacks.
    await Future.wait([
      for (final key in keys)
        _midi.stopNote(sfId: _sfId!, channel: _midiChannel, key: key),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _emitState(PlaybackStatus status, {String? error}) {
    _status = status;
    _stateController.add(PlaybackState(status: status, error: error));
  }
}
