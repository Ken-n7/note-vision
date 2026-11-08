import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/editor/domain/scan_key_correction.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

Score study() => NotationReviewService.ensureIdentity(
  Score(
    id: 'mapped-score',
    title: 'Key study',
    composer: '',
    parts: [
      for (var p = 0; p < 3; p++)
        Part(
          id: 'p$p',
          name: 'Row $p',
          measures: [
            for (var m = 0; m < 4; m++)
              Measure(
                number: m + 1,
                clef: m == 0 ? const Clef(sign: 'G', line: 2) : null,
                keySignature: m == 2
                    ? null
                    : KeySignature(fifths: m == 3 ? 0 : p + 1),
                symbols: const [
                  Note(step: 'C', octave: 4, duration: 2, type: 'quarter'),
                  Note(step: 'F', octave: 4, duration: 2, type: 'quarter'),
                  Note(
                    step: 'C',
                    octave: 4,
                    alter: 0,
                    duration: 2,
                    type: 'quarter',
                  ),
                ],
              ),
          ],
        ),
    ],
  ),
);

void main() {
  test(
    'selected openings change together; inherited nulls and later keys stay',
    () {
      final base = study();
      final plan = ScanKeyCorrection.prepare(base, {0, 1, 2}, 3);
      expect(plan.changes.map((c) => c.row), [0, 1]);
      expect(plan.changes.map((c) => c.end), [3, 3]);
      expect(plan.changes.map((c) => c.changedBars), [2, 2]);
      for (final p in [0, 1]) {
        expect(
          plan.preview.parts[p].measures.map((m) => m.keySignature?.fifths),
          [3, 3, null, 0],
        );
        for (var m = 0; m < 4; m++) {
          expect(
            identical(
              plan.preview.parts[p].measures[m].symbols,
              base.parts[p].measures[m].symbols,
            ),
            isTrue,
          );
        }
        expect(
          identical(
            plan.preview.parts[p].measures[3],
            base.parts[p].measures[3],
          ),
          isTrue,
        );
      }
      expect(identical(plan.preview.parts[2], base.parts[2]), isTrue);
    },
  );

  test('missing opening key is corrected without overwriting a later key', () {
    final original = study();
    final parts = original.parts.toList();
    parts[0] = parts[0].copyWith(
      measures: [
        parts[0].measures[0].copyWith(keySignature: null),
        parts[0].measures[1].copyWith(keySignature: null),
        parts[0].measures[2].copyWith(
          keySignature: const KeySignature(fifths: 0),
        ),
      ],
    );
    final plan = ScanKeyCorrection.prepare(original.copyWith(parts: parts), {
      0,
    }, -3);
    expect(plan.preview.parts[0].measures.map((m) => m.keySignature?.fifths), [
      -3,
      null,
      0,
    ]);
  });

  test('no-op, invalid key/row and stale previews cannot apply', () {
    final base = study();
    for (final plan in [
      ScanKeyCorrection.prepare(base, {}, 3),
      ScanKeyCorrection.prepare(base, {2}, 3),
      ScanKeyCorrection.prepare(base, {0}, 8),
      ScanKeyCorrection.prepare(base, {0, -1}, 3),
      ScanKeyCorrection.prepare(base, {3}, 3),
    ]) {
      expect(plan.hasChanges, isFalse);
      expect(plan.applyTo(base), isNull);
      expect(identical(plan.preview, base), isTrue);
    }
    final plan = ScanKeyCorrection.prepare(base, {0}, 3);
    expect(plan.applyTo(base.copyWith(title: 'Changed meanwhile')), isNull);
    expect(plan.applyTo(base), same(plan.preview));
  });

  test(
    'ensembles, imported documents, linked, tab and percussion are excluded',
    () {
      final base = study();
      expect(
        ScanKeyCorrection.supports(
          base.copyWith(playbackLayout: ScorePlaybackLayout.simultaneousParts),
        ),
        isFalse,
      );
      for (final part in [
        base.parts[0].copyWith(staff: 2),
        base.parts[0].copyWith(linked: true),
        base.parts[0].copyWith(staffLines: 1),
        base.parts[0].copyWith(
          measures: [
            base.parts[0].measures[0].copyWith(
              clef: const Clef(sign: 'TAB', line: 5),
            ),
          ],
        ),
        base.parts[0].copyWith(
          measures: [
            base.parts[0].measures[0].copyWith(
              clef: const Clef(sign: 'percussion', line: 2),
            ),
          ],
        ),
        base.parts[0].copyWith(measures: []),
      ]) {
        final other = base.copyWith(parts: [part, ...base.parts.skip(1)]);
        expect(ScanKeyCorrection.prepare(other, {0}, 3).hasChanges, isFalse);
      }
      expect(
        ScanKeyCorrection.supports(base.copyWith(parts: [base.parts.first])),
        isFalse,
      );
    },
  );

  test(
    'one history entry restores every row; undo/redo and JSON preserve the edit',
    () {
      final base = study();
      final plan = ScanKeyCorrection.prepare(base, {0, 1}, -2);
      final review = NotationReviewService.correction(
        base,
        plan.preview,
        NotationReviewService.issues(base).first,
        'Correct selected row keys',
      );
      final corrected = review.applyTo(base)!;
      expect(corrected.reviewHistory, hasLength(1));
      final state = EditorState(score: base).applyEdit(score: corrected);
      expect(state.undoStack, hasLength(1));
      expect(state.undo().score.toJson(), base.toJson());
      expect(state.undo().redo().score.toJson(), corrected.toJson());
      final saved = Score.fromJson(jsonDecode(jsonEncode(corrected.toJson())));
      final restored = NotationReviewService.restore(
        saved,
        saved.reviewHistory.last,
      )!;
      expect(
        restored.parts.map((p) => p.toJson()),
        base.parts.map((p) => p.toJson()),
      );
    },
  );

  test('playback and XML use corrected key while written natural stays', () {
    final base = study();
    final corrected = ScanKeyCorrection.prepare(base, {0}, 3).preview;
    List<int> midi(Score s) => const PlaybackConverter()
        .buildEvents(s)
        .where((e) => e.partIndex == 0 && e.measureIndex == 0)
        .map((e) => e.midiNote)
        .toList();
    expect(midi(base), [60, 66, 60]);
    expect(midi(corrected), [61, 66, 60]);
    final xml = XmlDocument.parse(
      MusicXmlExportService().toMusicXml(corrected),
    );
    final first = xml
        .findAllElements('part')
        .first
        .findElements('measure')
        .first;
    expect(first.findAllElements('fifths').single.innerText, '3');
    expect(
      first
          .findElements('note')
          .map((n) => n.getElement('pitch')?.getElement('alter')?.innerText),
      ['1', '1', null],
    );
    expect(
      first.findElements('note').last.getElement('accidental')?.innerText,
      'natural',
    );
  });

  test(
    'dense real-photo correction preserves every score field except selected keys',
    () {
      final detection = DetectionResult.fromJson(
        jsonDecode(
          File(
            'test/fixtures/barlines/dense.detection.json',
          ).readAsStringSync(),
        ),
      );
      final base = const DetectionToScoreMapperService().map(detection).score;
      final before = jsonEncode(base.toJson());
      final plan = ScanKeyCorrection.prepare(base, {0, 1, 2, 4, 5}, 3);
      expect(plan.changes, hasLength(5));
      expect(
        plan.preview.parts.map((p) => p.measures.first.keySignature?.fifths),
        List.filled(9, 3),
      );
      final stripped = plan.preview.toJson();
      for (var p = 0; p < base.parts.length; p++) {
        for (var m = 0; m < base.parts[p].measures.length; m++) {
          final bar = (stripped['parts'] as List)[p]['measures'][m] as Map;
          final old = base.parts[p].measures[m].keySignature;
          if (old == null) {
            bar.remove('keySignature');
          } else {
            bar['keySignature'] = old.toJson();
          }
        }
      }
      expect(jsonEncode(stripped), before);
      expect(jsonEncode(base.toJson()), before);
    },
  );
}
