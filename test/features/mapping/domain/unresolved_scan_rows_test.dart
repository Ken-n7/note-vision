import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/preprocessing/data/barline_finder.dart';

void main() {
  test(
    'a row without boundaries retains all explicit note values together',
    () {
      const staff = DetectedStaff(
        id: 's',
        topY: 90,
        bottomY: 150,
        lineYs: [100, 110, 120, 130, 140],
      );
      final result = const DetectionToScoreMapperService().map(
        DetectionResult(
          staffs: [staff],
          symbols: [
            const DetectedSymbol(
              id: 'g',
              type: 'clefG',
              x: 10,
              y: 95,
              width: 20,
              height: 50,
            ),
            for (var i = 0; i < 8; i++)
              DetectedSymbol(
                id: 'n$i',
                type: 'noteheadWholeOnLine',
                x: 60.0 + 30 * i,
                y: 130,
                width: 12,
                height: 8,
                metadata: const {'noteType': 'whole'},
              ),
          ],
        ),
      );
      final part = result.score.parts.single;
      expect(part.measures, hasLength(1));
      expect(part.measures.single.toJson()['unresolvedBarlines'], isTrue);
      expect(part.measures.single.notes.map((n) => n.reviewId), [
        for (var i = 0; i < 8; i++) 'n$i',
      ]);
      expect(
        part.measures.single.notes.every(
          (n) => n.type == 'whole' && n.duration == 8,
        ),
        isTrue,
      );
      expect(result.warnings.any((w) => w.contains('kept together')), isTrue);
    },
  );

  test('the unbarred uneven exercises stay as two complete source rows', () {
    const root = 'test/fixtures/barlines/ragged';
    final frozen = DetectionResult.fromJson(
      jsonDecode(File('$root.detection.json').readAsStringSync()),
    );
    final photo = img.grayscale(
      img.decodeJpg(File('$root.jpg').readAsBytesSync())!,
    );
    final lines = const BarlineFinder().find(
      photo,
      frozen.staffs,
      frozen.symbols,
    );
    final score = const DetectionToScoreMapperService()
        .map(
          DetectionResult(
            staffs: frozen.staffs,
            symbols: frozen.symbols,
            barlines: lines,
          ),
        )
        .score;
    expect(score.parts.map((p) => p.measures.length), [2, 2, 3, 4, 1, 1]);
    expect(
      score.parts.expand((p) => p.measures).expand((m) => m.notes),
      hasLength(96),
    );
    expect(score.parts[4].measures.single.notes, hasLength(21));
    expect(score.parts[5].measures.single.notes, hasLength(19));
    for (final p in score.parts.take(4)) {
      expect(
        p.measures.any((m) => m.toJson()['unresolvedBarlines'] == true),
        isFalse,
      );
    }
    for (final p in score.parts.skip(4)) {
      expect(p.measures.single.toJson()['unresolvedBarlines'], isTrue);
    }
  });

  test(
    'unresolved boundaries survive copies and JSON without changing old scores',
    () {
      final json = const Measure(number: 1, symbols: []).toJson();
      expect(json.containsKey('unresolvedBarlines'), isFalse);
      final row = Measure.fromJson({...json, 'unresolvedBarlines': true});
      expect(row.copyWith(number: 2).toJson()['unresolvedBarlines'], isTrue);
      expect(Measure.fromJson(row.toJson()).toJson(), row.toJson());
      expect(Measure.fromJson(json).toJson(), json);
    },
  );

  test(
    'review asks about missing boundaries without offering guessed splits',
    () {
      final score = Score.fromJson({
        'id': 'mapped-score',
        'title': '',
        'composer': '',
        'parts': [
          {
            'id': 'p',
            'name': 'Row',
            'measures': [
              {
                'number': 1,
                'unresolvedBarlines': true,
                'clef': {'sign': 'G', 'line': 2},
                'timeSignature': {'beats': 4, 'beatType': 4},
                'symbols': [
                  for (var i = 0; i < 8; i++)
                    Note(
                      step: 'C',
                      octave: 4,
                      type: 'quarter',
                      duration: 2,
                      reviewId: 'n$i',
                    ).toJson(),
                ],
              },
            ],
          },
        ],
      });
      final issues = NotationChecker.check(score);
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('No barlines were read'));
      expect(issues.single.hasFix, isFalse);
      expect(
        NotationReviewService.location(score, issues.single),
        'Row 1 · Barlines unconfirmed',
      );
      final copied = Score.fromJson(score.toJson());
      expect(
        NotationChecker.check(copied).single.message,
        issues.single.message,
      );
    },
  );
}
