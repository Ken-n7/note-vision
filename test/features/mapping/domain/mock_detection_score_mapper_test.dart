import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/mock_detection_score_mapper.dart';

void main() {
  const mapper = MockDetectionScoreMapper(
    mapper: DetectionToScoreMapperService(),
  );

  group('MockDetectionScoreMapper', () {
    test('maps a mock melody file into a valid score model', () async {
      final result = await _mapFixture(mapper, 'mock_melody.json');
      final score = result.score;
      final part = score.parts.single;
      final measure = part.measures.single;

      expect(result.errors, isEmpty);
      expect(score.title, isEmpty);
      expect(score.composer, isEmpty);
      expect(score.partCount, 1);
      expect(part.name, 'Treble');
      expect(measure.number, 1);
      expect(measure.clef?.sign, 'G');
      expect(measure.notes.map((note) => note.pitch).toList(), ['E4', 'F4']);
      expect(measure.notes.map((note) => note.type).toList(), [
        'quarter',
        'quarter',
      ]);
      expect(measure.symbols, everyElement(isA<Note>()));
    });

    test(
      'maps a mock file with rests into the expected score symbols',
      () async {
        final result = await _mapFixture(mapper, 'mock_with_rest.json');
        final measure = result.score.parts.single.measures.single;

        expect(result.errors, isEmpty);
        expect(measure.symbols, hasLength(2));
        expect(measure.symbols.first, isA<Rest>());
        expect(measure.symbols.last, isA<Note>());
        expect(measure.rests.single.type, 'quarter');
        expect(measure.notes.single.pitch, 'E4');
        expect(measure.notes.single.type, 'quarter');
      },
    );

    test(
      'creates multiple measures from barlines in supported mock files',
      () async {
        final result = await _mapFixture(mapper, 'mock_multi_measure.json');
        final measures = result.score.parts.single.measures;

        expect(result.errors, isEmpty);
        expect(measures, hasLength(3));
        expect(measures.map((measure) => measure.number).toList(), [1, 2, 3]);
        expect(measures[0].symbols.single, isA<Note>());
        expect(measures[1].symbols.single, isA<Rest>());
        expect(measures[2].symbols.single, isA<Note>());
        expect(measures[0].notes.single.pitch, 'E4');
        expect(measures[1].rests.single.type, 'quarter');
        expect(measures[2].notes.single.pitch, 'G4');
      },
    );
  });
}

Future<MappingResult> _mapFixture(
  MockDetectionScoreMapper mapper,
  String fileName,
) {
  return mapper.mapFile(_fixturePath(fileName));
}

String _fixturePath(String fileName) =>
    'test/features/mapping/domain/fixtures/mock_detection/$fileName';
