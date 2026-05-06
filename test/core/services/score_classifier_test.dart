import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/score_classifier.dart';

void main() {
  group('ScoreClassifier', () {
    test('labels a simple single-part score as Simple Melody', () {
      final score = _buildScore(
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'E', octave: 4, duration: 2, type: 'half'),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.simpleMelody);
    });

    test('labels a 2/4 single-part score as Children\'s Song before March', () {
      final score = _buildScore(
        timeSignature: const TimeSignature(beats: 2, beatType: 4),
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.childrensSong);
    });

    test('labels a 3/4 piece as Waltz', () {
      final score = _buildScore(
        timeSignature: const TimeSignature(beats: 3, beatType: 4),
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'G', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'A', octave: 4, duration: 1, type: 'quarter'),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.waltz);
    });

    test('labels a 2/4 piece without the children rule as March', () {
      final score = _buildScore(
        timeSignature: const TimeSignature(beats: 2, beatType: 4),
        keySignature: const KeySignature(fifths: 3),
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'eighth'),
          Note(step: 'E', octave: 5, duration: 1, type: 'sixteenth'),
          Note(step: 'A', octave: 5, duration: 1, type: 'sixteenth'),
          Note(step: 'C', octave: 6, duration: 1, type: 'eighth'),
          Note(step: 'E', octave: 6, duration: 1, type: 'eighth'),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.march);
    });

    test('labels a multi-part score with a complex key as Classical', () {
      final score = Score(
        id: 'classical',
        title: 'Classical',
        composer: 'Composer',
        parts: [
          _buildPart(
            measureNumber: 1,
            keySignature: const KeySignature(fifths: 4),
            notes: const [
              Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
            ],
          ),
          _buildPart(
            measureNumber: 1,
            keySignature: const KeySignature(fifths: 4),
            notes: const [
              Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
            ],
          ),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.classical);
    });

    test('labels a mixed 4/4 piece with no stronger rule as General Piece', () {
      final score = _buildScore(
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'eighth'),
          Note(step: 'E', octave: 5, duration: 1, type: 'eighth'),
          Note(step: 'G', octave: 5, duration: 1, type: 'whole'),
        ],
      );

      expect(ScoreClassifier.classify(score), ScoreLabel.generalPiece);
    });

    test('priority order keeps 2/4 simple pieces out of March', () {
      final score = _buildScore(
        timeSignature: const TimeSignature(beats: 2, beatType: 4),
        notes: const [
          Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'E', octave: 4, duration: 1, type: 'quarter'),
          Note(step: 'F', octave: 4, duration: 1, type: 'quarter'),
        ],
      );

      expect(ScoreClassifier.classify(score), isNot(ScoreLabel.march));
      expect(ScoreClassifier.classify(score), ScoreLabel.childrensSong);
    });
  });
}

Score _buildScore({
  TimeSignature timeSignature = const TimeSignature(beats: 4, beatType: 4),
  KeySignature keySignature = const KeySignature(fifths: 0),
  required List<Note> notes,
}) {
  return Score(
    id: 'score',
    title: 'Test',
    composer: 'Composer',
    parts: [
      _buildPart(
        measureNumber: 1,
        timeSignature: timeSignature,
        keySignature: keySignature,
        notes: notes,
      ),
    ],
  );
}

Part _buildPart({
  required int measureNumber,
  TimeSignature? timeSignature,
  KeySignature? keySignature,
  required List<Note> notes,
}) {
  return Part(
    id: 'P$measureNumber',
    name: 'Part $measureNumber',
    measures: [
      Measure(
        number: measureNumber,
        timeSignature: timeSignature,
        keySignature: keySignature,
        symbols: notes,
      ),
    ],
  );
}
