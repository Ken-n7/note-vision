import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/widgets/score_notation/score_notation_metrics.dart';
import 'package:note_vision/features/pdf/pdf_score_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfScoreRenderer layout', () {
    const renderer = PdfScoreRenderer();

    test('uses the same single-part page buckets as the editor', () {
      final score = _scoreWithPartMeasures(measureCount: 21);

      final pages = renderer.debugPageLayoutForTesting(score);

      expect(pages, hasLength(2));
      expect(pages[0].firstMeasureIndex, 0);
      expect(pages[0].measureCount, 20);
      expect(pages[0].measuresPerSystem, 4);
      expect(pages[0].rowsPerPage, 5);
      expect(pages[1].firstMeasureIndex, 20);
      expect(pages[1].measureCount, 1);
    });

    test('uses the same multi-part rows-per-page policy as the editor', () {
      final score = _scoreWithPartMeasures(measureCount: 13, partCount: 2);

      final pages = renderer.debugPageLayoutForTesting(score);

      expect(pages, hasLength(2));
      expect(pages[0].rowsPerPage, 3);
      expect(pages[0].measureCount, 12);
      expect(pages[1].firstMeasureIndex, 12);
      expect(pages[1].measureCount, 1);
    });

    test('honors explicit page breaks from editor/import flow', () {
      final score = _scoreWithMeasures([
        _measure(1),
        _measure(2, startsNewPage: true),
        _measure(3),
      ]);

      final pages = renderer.debugPageLayoutForTesting(score);

      expect(pages, hasLength(2));
      expect(pages[0].firstMeasureIndex, 0);
      expect(pages[0].measureCount, 1);
      expect(pages[1].firstMeasureIndex, 1);
      expect(pages[1].measureCount, 2);
    });

    test('carries inherited metadata onto later PDF pages', () {
      final first = _measure(
        1,
        clef: const Clef(sign: 'F', line: 4),
        keySignature: const KeySignature(fifths: -1),
        timeSignature: const TimeSignature(beats: 3, beatType: 4),
      );
      final score = _scoreWithMeasures([
        first,
        for (var i = 2; i <= 21; i++) _measure(i),
      ]);

      final pageTwoParts = renderer.debugPageSliceForTesting(score, 1);
      final firstVisible = pageTwoParts.single.single;

      expect(firstVisible.number, 21);
      expect(firstVisible.clef?.sign, 'F');
      expect(firstVisible.clef?.line, 4);
      expect(firstVisible.keySignature?.fifths, -1);
      expect(firstVisible.timeSignature?.beats, 3);
      expect(firstVisible.timeSignature?.beatType, 4);
    });

    test('normalizes score metadata for the first-page header', () {
      final score = Score(
        id: 'score',
        title: '  Moonlight Study  ',
        composer: '  L. Composer  ',
        parts: const [],
      );

      final header = renderer.debugHeaderLayoutForTesting(score);

      expect(header.title, 'Moonlight Study');
      expect(header.composer, 'L. Composer');
      expect(header.firstPageStaffOffset, greaterThan(0));
    });

    test('uses an untitled fallback for blank PDF titles', () {
      const score = Score(id: 'score', title: '   ', composer: '', parts: []);

      final header = renderer.debugHeaderLayoutForTesting(score);

      expect(header.title, 'Untitled Score');
      expect(header.composer, isEmpty);
    });
  });

  group('PdfScoreRenderer symbols', () {
    test('maps note accidentals to shared music glyphs', () {
      const renderer = PdfScoreRenderer();

      expect(
        renderer.accidentalLabelForTesting(1),
        ScoreNotationMetrics.sharpGlyph,
      );
      expect(
        renderer.accidentalLabelForTesting(-1),
        ScoreNotationMetrics.flatGlyph,
      );
      expect(
        renderer.accidentalLabelForTesting(0),
        ScoreNotationMetrics.naturalGlyph,
      );
      expect(
        renderer.accidentalLabelForTesting(2),
        ScoreNotationMetrics.doubleSharpGlyph,
      );
      expect(
        renderer.accidentalLabelForTesting(-2),
        ScoreNotationMetrics.doubleFlatGlyph,
      );
      expect(renderer.accidentalLabelForTesting(null), isNull);
    });

    test('renders music accidentals with embedded PDF font', () async {
      const renderer = PdfScoreRenderer(compress: false);
      final score = _scoreWithMeasures([
        const Measure(
          number: 1,
          clef: Clef(sign: 'G', line: 2),
          symbols: [
            Note(step: 'C', octave: 4, alter: 2, duration: 2, type: 'quarter'),
            Note(step: 'D', octave: 4, alter: -2, duration: 2, type: 'quarter'),
          ],
        ),
      ]);

      final bytes = await renderer.render(score);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('maps pitches using PDF y-up coordinates', () {
      const renderer = PdfScoreRenderer();
      const staffBottom = 100.0;

      final c4 = renderer.debugPitchYForTesting(
        step: 'C',
        octave: 4,
        staffBottom: staffBottom,
      );
      final g4 = renderer.debugPitchYForTesting(
        step: 'G',
        octave: 4,
        staffBottom: staffBottom,
      );

      expect(c4, lessThan(staffBottom));
      expect(g4, greaterThan(staffBottom));
    });
  });
}

Score _scoreWithPartMeasures({required int measureCount, int partCount = 1}) {
  return Score(
    id: 'score',
    title: 'Score',
    composer: '',
    parts: [
      for (var part = 0; part < partCount; part++)
        Part(
          id: 'P${part + 1}',
          name: 'Part ${part + 1}',
          measures: [for (var i = 1; i <= measureCount; i++) _measure(i)],
        ),
    ],
  );
}

Score _scoreWithMeasures(List<Measure> measures) {
  return Score(
    id: 'score',
    title: 'Score',
    composer: '',
    parts: [Part(id: 'P1', name: 'Part 1', measures: measures)],
  );
}

Measure _measure(
  int number, {
  bool startsNewPage = false,
  Clef? clef,
  KeySignature? keySignature,
  TimeSignature? timeSignature,
}) {
  return Measure(
    number: number,
    clef: clef,
    keySignature: keySignature,
    timeSignature: timeSignature,
    startsNewPage: startsNewPage,
    symbols: const [Rest(duration: 2, type: 'quarter')],
  );
}
