import 'dart:async';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import '../models/note.dart';
import '../models/rest.dart';
import '../models/score.dart';

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
// Internal event model
// ---------------------------------------------------------------------------

class _PlaybackEvent {
  const _PlaybackEvent({
    required this.partIndex,
    required this.measureIndex,
    required this.symbolIndex,
    required this.midiNote,
    required this.baseDurationMs,
  });

  final int partIndex;
  final int measureIndex;
  final int symbolIndex;

  /// -1 means this event is a rest — no MIDI note is sounded.
  final int midiNote;

  /// Duration in ms at [PlaybackService._defaultTempo] BPM.
  final int baseDurationMs;

  bool get isRest => midiNote < 0;
}

// ---------------------------------------------------------------------------
// PlaybackService
// ---------------------------------------------------------------------------

/// Singleton service that synthesises a [Score] to MIDI audio via
/// flutter_midi_pro (FluidSynth on Android, AVFoundation on iOS/macOS).
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
  static const int _defaultTempo = 120;

  // ── Step → semitone offset (C = 0) ────────────────────────────────────
  static const Map<String, int> _stepOffset = {
    'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
  };

  // ── State ──────────────────────────────────────────────────────────────
  final MidiPro _midi = MidiPro();
  int? _sfId;
  bool _initialized = false;

  int _tempo = _defaultTempo;
  PlaybackStatus _status = PlaybackStatus.stopped;

  // Playback loop control
  bool _shouldPlay = false;
  Timer? _noteTimer;
  Completer<bool>? _waitCompleter;

  // Flat event list built on each play() call
  List<_PlaybackEvent> _events = const [];
  int _currentEventIndex = 0;

  // ── Streams ────────────────────────────────────────────────────────────
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _positionController = StreamController<PlaybackPosition>.broadcast();

  Stream<PlaybackState> get stateStream => _stateController.stream;
  Stream<PlaybackPosition> get positionStream => _positionController.stream;

  PlaybackStatus get status => _status;
  int get tempo => _tempo;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Loads the soundfont asset. Safe to call multiple times — no-ops once
  /// initialized. Must be called before [play].
  Future<void> init() async {
    if (_initialized) return;
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
    }
  }

  // ── Playback control ───────────────────────────────────────────────────

  /// Starts playback from the beginning. Safe to call while already playing
  /// (stops previous playback first).
  Future<void> play(Score score) async {
    if (_status == PlaybackStatus.playing) stop();
    if (!_initialized) await init();
    if (_status == PlaybackStatus.error) return;

    _events = _buildEvents(score);
    if (_events.isEmpty) return;

    _currentEventIndex = 0;
    _shouldPlay = true;
    _emitState(PlaybackStatus.playing);
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
      final durationMs = _scaledDuration(event.baseDurationMs);
      final completed = await _waitMs(durationMs);

      // Stop the note before advancing to the next event.
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

  /// Scales a base-120-BPM duration to the current [_tempo].
  int _scaledDuration(int baseDurationMs) =>
      (baseDurationMs * _defaultTempo / _tempo).round();

  // ── Score → event list ─────────────────────────────────────────────────

  /// Flattens the [Score] into a sequential list of [_PlaybackEvent]s.
  ///
  /// All parts are included in order. For a grand-staff score this means
  /// treble part plays first, then bass part — adequate for a demo.
  /// (Full interleaved simultaneous playback is a future improvement.)
  List<_PlaybackEvent> _buildEvents(Score score) {
    final events = <_PlaybackEvent>[];
    for (var pi = 0; pi < score.parts.length; pi++) {
      final part = score.parts[pi];
      for (var mi = 0; mi < part.measures.length; mi++) {
        final measure = part.measures[mi];
        for (var si = 0; si < measure.symbols.length; si++) {
          final symbol = measure.symbols[si];
          if (symbol is Note) {
            final midiNote = _noteToMidi(symbol);
            if (midiNote < 0) continue; // invalid pitch — skip
            events.add(_PlaybackEvent(
              partIndex: pi,
              measureIndex: mi,
              symbolIndex: si,
              midiNote: midiNote,
              baseDurationMs: _durationMs(symbol.duration),
            ));
          } else if (symbol is Rest) {
            events.add(_PlaybackEvent(
              partIndex: pi,
              measureIndex: mi,
              symbolIndex: si,
              midiNote: -1,
              baseDurationMs: _durationMs(symbol.duration),
            ));
          }
        }
      }
    }
    return events;
  }

  /// Converts a [Note] to a MIDI key number (0–127).
  ///
  /// Formula:  (octave + 1) × 12  +  stepOffset  +  alter
  ///   C4 → (4+1)×12 + 0       = 60  ✓ middle C
  ///   A4 → (4+1)×12 + 9       = 69  ✓ concert A
  int _noteToMidi(Note note) {
    final offset = _stepOffset[note.step.toUpperCase()];
    if (offset == null) return -1;
    final midi = (note.octave + 1) * 12 + offset + (note.alter ?? 0);
    return midi.clamp(0, 127);
  }

  /// Converts MusicXML division count to ms at [_defaultTempo] BPM.
  ///
  /// Project division convention: whole=8, half=4, quarter=2, eighth=1
  ///
  ///   durationMs = divisions × (60 000 / bpm) / 2
  ///             = divisions × 30 000 / 120
  ///             = divisions × 250  (at 120 BPM)
  int _durationMs(int divisions) =>
      (divisions * 30000 ~/ _defaultTempo).clamp(50, 16000);
}
