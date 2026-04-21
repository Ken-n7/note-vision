// Tests for PlaybackConverter — the pure-Dart Score → MIDI event conversion
// layer used by PlaybackService.
//
// PlaybackService itself depends on flutter_midi_pro (native plugin) and is
// not exercised here. All conversion logic lives in PlaybackConverter, which
// has no platform dependencies and can be tested fully in a VM runner.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/playback_service.dart'
    show PlaybackPosition;

void main() {
  const converter = PlaybackConverter();

  // ──────────────────────────────────────────────────────────────────────────
  // MIDI note number — noteToMidi
  // ──────────────────────────────────────────────────────────────────────────
  group('noteToMidi — pitch formula', () {
    test('C4 is MIDI 60 (middle C)', () {
      expect(
        converter.noteToMidi(
          const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
        ),
        60,
      );
    });

    test('A4 is MIDI 69 (concert A)', () {
      expect(
        converter.noteToMidi(
          const Note(step: 'A', octave: 4, duration: 2, type: 'quarter'),
        ),
        69,
      );
    });

    test('C5 is MIDI 72', () {
      expect(
        converter.noteToMidi(
          const Note(step: 'C', octave: 5, duration: 2, type: 'quarter'),
        ),
        72,
      );
    });

    test('B3 is MIDI 59', () {
      expect(
        converter.noteToMidi(
          const Note(step: 'B', octave: 3, duration: 2, type: 'quarter'),
        ),
        59,
      );
    });

    test('all natural notes in octave 4 match chromatic scale from C4=60', () {
      final expected = {
        'C': 60,
        'D': 62,
        'E': 64,
        'F': 65,
        'G': 67,
        'A': 69,
        'B': 71,
      };
      for (final entry in expected.entries) {
        final midi = converter.noteToMidi(
          Note(step: entry.key, octave: 4, duration: 2, type: 'quarter'),
        );
        expect(
          midi,
          entry.value,
          reason: '${entry.key}4 should be ${entry.value}',
        );
      }
    });

    test('sharp raises pitch by 1 semitone', () {
      // C#4 = 61, F#4 = 66
      expect(
        converter.noteToMidi(
          const Note(
            step: 'C',
            octave: 4,
            alter: 1,
            duration: 2,
            type: 'quarter',
          ),
        ),
        61,
      );
      expect(
        converter.noteToMidi(
          const Note(
            step: 'F',
            octave: 4,
            alter: 1,
            duration: 2,
            type: 'quarter',
          ),
        ),
        66,
      );
    });

    test('flat lowers pitch by 1 semitone', () {
      // Bb4 = 70, Eb4 = 63
      expect(
        converter.noteToMidi(
          const Note(
            step: 'B',
            octave: 4,
            alter: -1,
            duration: 2,
            type: 'quarter',
          ),
        ),
        70,
      );
      expect(
        converter.noteToMidi(
          const Note(
            step: 'E',
            octave: 4,
            alter: -1,
            duration: 2,
            type: 'quarter',
          ),
        ),
        63,
      );
    });

    test('double sharp raises pitch by 2 semitones', () {
      // Cx4 (C double-sharp) = 62
      expect(
        converter.noteToMidi(
          const Note(
            step: 'C',
            octave: 4,
            alter: 2,
            duration: 2,
            type: 'quarter',
          ),
        ),
        62,
      );
    });

    test('double flat lowers pitch by 2 semitones', () {
      // Bbb4 = 69
      expect(
        converter.noteToMidi(
          const Note(
            step: 'B',
            octave: 4,
            alter: -2,
            duration: 2,
            type: 'quarter',
          ),
        ),
        69,
      );
    });

    test('null alter treated as 0 (natural)', () {
      expect(
        converter.noteToMidi(
          const Note(
            step: 'G',
            octave: 4,
            alter: null,
            duration: 2,
            type: 'quarter',
          ),
        ),
        67,
      );
    });

    test('step lookup is case-insensitive', () {
      expect(
        converter.noteToMidi(
          const Note(step: 'c', octave: 4, duration: 2, type: 'quarter'),
        ),
        60,
      );
      expect(
        converter.noteToMidi(
          const Note(step: 'a', octave: 4, duration: 2, type: 'quarter'),
        ),
        69,
      );
    });

    test('result is clamped to 0–127', () {
      // Extremely low note — clamp to 0
      expect(
        converter.noteToMidi(
          const Note(step: 'C', octave: -2, duration: 2, type: 'quarter'),
        ),
        0,
      );
      // Extremely high note — clamp to 127
      expect(
        converter.noteToMidi(
          const Note(step: 'G', octave: 10, duration: 2, type: 'quarter'),
        ),
        127,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Duration calculation — durationMs
  // ──────────────────────────────────────────────────────────────────────────
  group('durationMs — divisions to milliseconds at 120 BPM', () {
    // At 120 BPM: quarter (2 divisions) = 500 ms → 1 division = 250 ms
    test('whole note (divisions=8) → 2000 ms', () {
      expect(converter.durationMs(8), 2000);
    });

    test('half note (divisions=4) → 1000 ms', () {
      expect(converter.durationMs(4), 1000);
    });

    test('quarter note (divisions=2) → 500 ms', () {
      expect(converter.durationMs(2), 500);
    });

    test('eighth note (divisions=1) → 250 ms', () {
      expect(converter.durationMs(1), 250);
    });

    test('result is proportional — half lasts twice as long as quarter', () {
      expect(converter.durationMs(4), converter.durationMs(2) * 2);
    });

    test('result is proportional — whole lasts four times quarter', () {
      expect(converter.durationMs(8), converter.durationMs(2) * 4);
    });

    test('zero divisions clamps to minimum (50 ms)', () {
      expect(converter.durationMs(0), 50);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Tempo scaling — scaledDuration
  // ──────────────────────────────────────────────────────────────────────────
  group('scaledDuration — tempo adjustment', () {
    test('at default tempo (120 BPM) returns base duration unchanged', () {
      expect(converter.scaledDuration(500, 120), 500);
      expect(converter.scaledDuration(250, 120), 250);
    });

    test('60 BPM plays twice as slow as 120 BPM', () {
      expect(converter.scaledDuration(500, 60), 1000);
    });

    test('240 BPM plays twice as fast as 120 BPM', () {
      expect(converter.scaledDuration(500, 240), 250);
    });

    test('90 BPM scales correctly', () {
      // 500 × 120/90 = 666.67 → rounds to 667
      expect(converter.scaledDuration(500, 90), 667);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Event building — buildEvents
  // ──────────────────────────────────────────────────────────────────────────
  group('buildEvents — Score → PlaybackEvent list', () {
    test('empty score produces no events', () {
      final score = _score([]);
      expect(converter.buildEvents(score), isEmpty);
    });

    test('score with only empty measures produces no events', () {
      final score = _score([
        _part([_measure([])]),
      ]);
      expect(converter.buildEvents(score), isEmpty);
    });

    test('single note produces one event with correct midi and duration', () {
      final score = _score([
        _part([
          _measure([
            const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events, hasLength(1));
      expect(events[0].midiNote, 60);
      expect(events[0].baseDurationMs, 500);
      expect(events[0].isRest, isFalse);
      expect(events[0].partIndex, 0);
      expect(events[0].measureIndex, 0);
      expect(events[0].symbolIndex, 0);
    });

    test('rest produces one event with midiNote=-1', () {
      final score = _score([
        _part([
          _measure([const Rest(duration: 2, type: 'quarter')]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events, hasLength(1));
      expect(events[0].isRest, isTrue);
      expect(events[0].midiNote, -1);
      expect(events[0].baseDurationMs, 500);
    });

    test('events appear in measure then symbol order', () {
      final score = _score([
        _part([
          _measure([
            const Note(
              step: 'C',
              octave: 4,
              duration: 2,
              type: 'quarter',
            ), // C4
            const Note(
              step: 'E',
              octave: 4,
              duration: 2,
              type: 'quarter',
            ), // E4
            const Note(
              step: 'G',
              octave: 4,
              duration: 2,
              type: 'quarter',
            ), // G4
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events.map((e) => e.midiNote), [60, 64, 67]);
      expect(events.map((e) => e.symbolIndex), [0, 1, 2]);
    });

    test('events across multiple measures carry correct measureIndex', () {
      final score = _score([
        _part([
          _measure([
            const Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
          ]),
          _measure([
            const Note(step: 'G', octave: 4, duration: 2, type: 'quarter'),
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events[0].measureIndex, 0);
      expect(events[1].measureIndex, 1);
    });

    test('events across multiple parts carry correct partIndex', () {
      final score = _score([
        _part([
          _measure([
            const Note(step: 'C', octave: 5, duration: 2, type: 'quarter'),
          ]),
        ]), // treble
        _part([
          _measure([
            const Note(step: 'C', octave: 3, duration: 2, type: 'quarter'),
          ]),
        ]), // bass
      ]);
      final events = converter.buildEvents(score);
      expect(events, hasLength(2));
      expect(events[0].partIndex, 0);
      expect(events[0].midiNote, 72); // C5
      expect(events[1].partIndex, 1);
      expect(events[1].midiNote, 48); // C3
    });

    test('mixed notes and rests produce events in order', () {
      final score = _score([
        _part([
          _measure([
            const Note(step: 'A', octave: 4, duration: 2, type: 'quarter'),
            const Rest(duration: 4, type: 'half'),
            const Note(step: 'B', octave: 4, duration: 1, type: 'eighth'),
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events, hasLength(3));
      expect(events[0].isRest, isFalse);
      expect(events[0].midiNote, 69); // A4
      expect(events[1].isRest, isTrue);
      expect(events[1].baseDurationMs, 1000); // half = 1000 ms
      expect(events[2].isRest, isFalse);
      expect(events[2].midiNote, 71); // B4
      expect(events[2].baseDurationMs, 250); // eighth = 250 ms
    });

    test('notes with accidentals produce correct MIDI numbers', () {
      final score = _score([
        _part([
          _measure([
            const Note(
              step: 'F',
              octave: 4,
              alter: 1,
              duration: 2,
              type: 'quarter',
            ), // F#4 = 66
            const Note(
              step: 'B',
              octave: 4,
              alter: -1,
              duration: 2,
              type: 'quarter',
            ), // Bb4 = 70
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events[0].midiNote, 66); // F#4
      expect(events[1].midiNote, 70); // Bb4
    });

    test('whole and eighth durations are correct', () {
      final score = _score([
        _part([
          _measure([
            const Note(
              step: 'C',
              octave: 4,
              duration: 8,
              type: 'whole',
            ), // 2000 ms
            const Note(
              step: 'C',
              octave: 4,
              duration: 1,
              type: 'eighth',
            ), // 250 ms
          ]),
        ]),
      ]);
      final events = converter.buildEvents(score);
      expect(events[0].baseDurationMs, 2000);
      expect(events[1].baseDurationMs, 250);
    });

    test('no crash on score with only rests', () {
      final score = _score([
        _part([
          _measure([
            const Rest(duration: 8, type: 'whole'),
            const Rest(duration: 4, type: 'half'),
          ]),
        ]),
      ]);
      expect(() => converter.buildEvents(score), returnsNormally);
      final events = converter.buildEvents(score);
      expect(events, hasLength(2));
      expect(events.every((e) => e.isRest), isTrue);
    });

    test('PlaybackEvent.isRest is false for notes, true for rests', () {
      final noteEvent = PlaybackEvent(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 0,
        midiNote: 60,
        baseDurationMs: 500,
      );
      final restEvent = PlaybackEvent(
        partIndex: 0,
        measureIndex: 0,
        symbolIndex: 1,
        midiNote: -1,
        baseDurationMs: 500,
      );
      expect(noteEvent.isRest, isFalse);
      expect(restEvent.isRest, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // PlaybackPosition
  // ──────────────────────────────────────────────────────────────────────────
  group('PlaybackPosition', () {
    test('none sentinel has partIndex < 0', () {
      expect(PlaybackPosition.none.isNone, isTrue);
      expect(PlaybackPosition.none.partIndex, -1);
    });

    test('equality works correctly', () {
      const a = PlaybackPosition(partIndex: 0, measureIndex: 2, symbolIndex: 3);
      const b = PlaybackPosition(partIndex: 0, measureIndex: 2, symbolIndex: 3);
      const c = PlaybackPosition(partIndex: 0, measureIndex: 2, symbolIndex: 4);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}

// ── Test helpers ─────────────────────────────────────────────────────────────

Score _score(List<Part> parts) =>
    Score(id: 'test', title: 'Test Score', composer: '', parts: parts);

Part _part(List<Measure> measures) =>
    Part(id: 'p1', name: 'Test', measures: measures);

Measure _measure(List<dynamic> symbols, {int number = 1}) => Measure(
  number: number,
  clef: const Clef(sign: 'G', line: 2),
  symbols: symbols.cast(),
);
