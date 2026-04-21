import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';

void main() {
  group('Score symbol edit helpers', () {
    test('getSymbolAt returns symbol or null when out of range', () {
      final score = _buildScore();

      expect(score.getSymbolAt(0, 0, 0), isA<Note>());
      expect(score.getSymbolAt(0, 0, 1), isA<Rest>());
      expect(score.getSymbolAt(1, 0, 0), isNull);
      expect(score.getSymbolAt(0, 1, 0), isNull);
      expect(score.getSymbolAt(0, 0, 2), isNull);
      expect(score.getSymbolAt(-1, 0, 0), isNull);
    });

    test('replaceSymbolAt returns updated immutable score', () {
      final score = _buildScore();
      const replacement = Note(step: 'E', octave: 4, duration: 2, type: 'half');

      final next = score.replaceSymbolAt(0, 0, 0, replacement);

      expect(identical(next, score), isFalse);
      expect(next.getSymbolAt(0, 0, 0), replacement);
      expect(score.getSymbolAt(0, 0, 0), isNot(replacement));
    });

    test('deleteSymbolAt removes symbol and shifts left', () {
      final score = _buildScore();

      final next = score.deleteSymbolAt(0, 0, 0);

      expect(next.parts[0].measures[0].symbols.length, 1);
      expect(next.getSymbolAt(0, 0, 0), isA<Rest>());
      expect(score.parts[0].measures[0].symbols.length, 2);
    });

    test('insertSymbolAt inserts at index and shifts right', () {
      final score = _buildScore();
      const inserted = Note(step: 'G', octave: 5, duration: 1, type: 'quarter');

      final next = score.insertSymbolAt(0, 0, 1, inserted);

      expect(next.parts[0].measures[0].symbols.length, 3);
      expect(next.getSymbolAt(0, 0, 0), isA<Note>());
      expect(next.getSymbolAt(0, 0, 1), inserted);
      expect(next.getSymbolAt(0, 0, 2), isA<Rest>());
    });

    test('reorderSymbol moves symbol within same measure', () {
      final score = _buildScore().insertSymbolAt(
        0,
        0,
        2,
        const Note(step: 'D', octave: 4, duration: 1, type: 'quarter'),
      );

      final next = score.reorderSymbol(0, 0, 0, 2);

      expect(next.parts[0].measures[0].symbols.length, 3);
      expect(next.getSymbolAt(0, 0, 0), isA<Rest>());
      expect(next.getSymbolAt(0, 0, 2), isA<Note>());
    });

    test('invalid indices return original score for write helpers', () {
      final score = _buildScore();
      const symbol = Note(step: 'B', octave: 3, duration: 1, type: 'quarter');

      expect(identical(score.replaceSymbolAt(9, 0, 0, symbol), score), isTrue);
      expect(identical(score.deleteSymbolAt(0, 9, 0), score), isTrue);
      expect(identical(score.insertSymbolAt(0, 0, 9, symbol), score), isTrue);
      expect(identical(score.reorderSymbol(0, 0, 0, 9), score), isTrue);
    });
  });
}

Score _buildScore() {
  return const Score(
    id: 'score-1',
    title: 'Sample',
    composer: 'Composer',
    parts: [
      Part(
        id: 'part-1',
        name: 'Piano',
        measures: [
          Measure(
            number: 1,
            symbols: [
              Note(step: 'C', octave: 4, duration: 1, type: 'quarter'),
              Rest(duration: 1, type: 'quarter'),
            ],
          ),
        ],
      ),
    ],
  );
}
