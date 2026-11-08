import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/core/services/notation_checker.dart';
import 'package:note_vision/core/services/notation_review_service.dart';
import 'package:note_vision/core/services/playback_converter.dart';
import 'package:note_vision/core/services/score_source_service.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';
import 'package:note_vision/features/editor/model/editor_state_history.dart';
import 'package:note_vision/features/mapping/domain/detection_to_score_mapper_service.dart';
import 'package:note_vision/features/musicXML/musicxml_export_service.dart';
import 'package:xml/xml.dart';

Score reviewScore() => const Score(
  id: 'mapped-score',
  title: 'Unassigned marks',
  composer: '',
  parts: [
    Part(
      id: 'p',
      name: 'Row 1',
      measures: [
        Measure(
          number: 1,
          reviewId: 'bar',
          clef: Clef(sign: 'G', line: 2),
          timeSignature: TimeSignature(beats: 4, beatType: 4),
          unassignedAccidentals: [
            UnassignedAccidental(
              id: 'sharp',
              alter: 1,
              source: SourceRegion(
                pageId: 'photo',
                x: .1,
                y: .2,
                width: .03,
                height: .2,
              ),
            ),
            UnassignedAccidental(
              id: 'flat',
              alter: -1,
              source: SourceRegion(
                pageId: 'photo',
                x: .3,
                y: .2,
                width: .03,
                height: .2,
              ),
            ),
          ],
          symbols: [
            Note(
              step: 'C',
              octave: 4,
              duration: 2,
              type: 'quarter',
              reviewId: 'first',
            ),
            Note(
              step: 'C',
              octave: 4,
              duration: 2,
              type: 'quarter',
              reviewId: 'second',
            ),
            Rest(duration: 4, type: 'half', reviewId: 'rest'),
          ],
        ),
        Measure(
          number: 2,
          reviewId: 'next-bar',
          symbols: [
            Note(
              step: 'C',
              octave: 4,
              duration: 8,
              type: 'whole',
              reviewId: 'next',
            ),
          ],
        ),
      ],
    ),
  ],
);

List<NotationIssue> marks(Score score) => NotationReviewService.issues(
  score,
).where((i) => i.kind == NotationIssueKind.unassignedAccidental).toList();

DetectionResult detection({
  double x = 180,
  bool collision = false,
  bool key = false,
  bool noClef = false,
}) => DetectionResult(
  imageId: 'stray-mark',
  staffs: const [
    DetectedStaff(
      id: 'staff',
      topY: 90,
      bottomY: 155,
      lineYs: [100, 110, 120, 130, 140],
    ),
  ],
  symbols: [
    if (!noClef)
      const DetectedSymbol(
        id: 'clef',
        type: 'clefG',
        x: 5,
        y: 90,
        width: 15,
        height: 50,
      ),
    const DetectedSymbol(
      id: 'first',
      type: 'noteheadBlackInSpace',
      x: 50,
      y: 126,
      width: 12,
      height: 8,
    ),
    DetectedSymbol(
      id: 'mark',
      type: 'accidentalSharp',
      x: key ? 30 : x,
      y: 116,
      width: 8,
      height: 20,
    ),
    if (collision)
      const DetectedSymbol(
        id: 'other-mark',
        type: 'accidentalFlat',
        x: 82,
        y: 114,
        width: 8,
        height: 20,
      ),
    const DetectedSymbol(
      id: 'second',
      type: 'noteheadBlackInSpace',
      x: 100,
      y: 126,
      width: 12,
      height: 8,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mapper = DetectionToScoreMapperService();

  test('unassigned body mark is retained without changing the music', () {
    final score = mapper.map(detection()).score;
    final bar = score.parts.single.measures.single;
    expect(bar.unassignedAccidentals.single.id, 'mark');
    expect(bar.unassignedAccidentals.single.source?.x, 180);
    expect(bar.notes.map((n) => n.alter), [null, null]);
    expect(marks(score), hasLength(1));
  });

  test('a matched accidental is not also flagged as unassigned', () {
    final bar = mapper.map(detection(x: 80)).score.parts.single.measures.single;
    expect(bar.unassignedAccidentals, isEmpty);
    expect(bar.notes.last.alter, 1);
  });

  test('a key glyph is not offered as a note-level assignment', () {
    final bar = mapper
        .map(detection(key: true))
        .score
        .parts
        .single
        .measures
        .single;
    expect(bar.keySignature?.fifths, 1);
    expect(bar.unassignedAccidentals, isEmpty);
  });

  test('a collision retains the overwritten mark for review', () {
    final bar = mapper
        .map(detection(x: 75, collision: true))
        .score
        .parts
        .single
        .measures
        .single;
    expect(bar.notes.last.alter, -1);
    expect(bar.unassignedAccidentals.map((a) => a.id), ['mark']);
  });

  test('a mark bound to an unbuilt note is not silently lost', () {
    final score = mapper.map(detection(x: 80, noClef: true)).score;
    expect(score.parts.single.measures.single.notes, isEmpty);
    expect(marks(score).single.unassignedAccidental?.id, 'mark');
  });

  test('old score JSON and ordinary measure copies remain compatible', () {
    final original = reviewScore();
    final json = original.toJson();
    ((json['parts'] as List).first['measures'] as List).first.remove(
      'unassignedAccidentals',
    );
    expect(marks(Score.fromJson(json)), isEmpty);
    final bar = original.parts.single.measures.first;
    expect(
      bar.copyWith(number: 8).unassignedAccidentals,
      bar.unassignedAccidentals,
    );
  });

  test('each mark has a stable, separate question after save/reorder', () {
    final score = reviewScore();
    final originalKeys = marks(
      score,
    ).map((i) => NotationReviewService.key(score, i)).toSet();
    expect(originalKeys, hasLength(2));
    final moved = score.insertMeasureAfterInAllParts(-1);
    final loaded = Score.fromJson(jsonDecode(jsonEncode(moved.toJson())));
    expect(
      marks(loaded).map((i) => NotationReviewService.key(loaded, i)).toSet(),
      originalKeys,
    );
  });

  test(
    'assignment changes only the chosen note and consumes only its mark',
    () {
      final score = reviewScore();
      final changed = NotationReviewService.assignAccidental(
        score,
        marks(score).first,
        1,
      )!;
      final bar = changed.parts.single.measures.first;
      expect(bar.notes.map((n) => n.alter), [null, 1]);
      expect(bar.notes.map((n) => n.reviewId), ['first', 'second']);
      expect(bar.unassignedAccidentals.map((a) => a.id), ['flat']);
      final expected = score.toJson();
      final m = expected['parts'][0]['measures'][0];
      m['symbols'][1]['alter'] = 1;
      (m['unassignedAccidentals'] as List).removeAt(0);
      expect(changed.toJson(), expected);
    },
  );

  test(
    'rest, invalid indices and stale evidence cannot receive an assignment',
    () {
      final score = reviewScore(), issue = marks(reviewScore()).first;
      for (final i in [-1, 2, 99]) {
        expect(NotationReviewService.assignAccidental(score, issue, i), isNull);
      }
      final changed = NotationReviewService.assignAccidental(score, issue, 0)!;
      expect(NotationReviewService.assignAccidental(changed, issue, 1), isNull);
    },
  );

  test('ignore is per mark and survives save; restore reopens it', () {
    final score = reviewScore(), issue = marks(reviewScore()).first;
    final kept = NotationReviewService.keep(score, issue);
    final loaded = Score.fromJson(jsonDecode(jsonEncode(kept.toJson())));
    expect(marks(loaded).single.unassignedAccidental?.id, 'flat');
    expect(
      loaded.parts.single.measures.first.unassignedAccidentals,
      hasLength(2),
    );
    expect(
      marks(
        NotationReviewService.restore(loaded, loaded.reviewHistory.single)!,
      ),
      hasLength(2),
    );
  });

  test('deferred mark questions survive save and can resume', () {
    final score = reviewScore(), issue = marks(reviewScore()).first;
    final deferred = NotationReviewService.deferBar(score, issue);
    final loaded = Score.fromJson(jsonDecode(jsonEncode(deferred.toJson())));
    expect(
      marks(loaded).every((i) => NotationReviewService.isDeferred(loaded, i)),
      isTrue,
    );
    final resumed = NotationReviewService.resumeBar(
      loaded,
      marks(loaded).first,
    );
    expect(
      marks(resumed).any((i) => NotationReviewService.isDeferred(resumed, i)),
      isFalse,
    );
  });

  test('assignment and history undo/redo and restore together', () {
    final score = reviewScore(), issue = marks(reviewScore()).first;
    final next = NotationReviewService.assignAccidental(score, issue, 0)!;
    final applied = NotationReviewService.correction(
      score,
      next,
      issue,
      'Assign sharp',
    ).applyTo(score)!;
    final state = EditorState(score: score).applyEdit(score: applied);
    expect(state.undo().score.toJson(), score.toJson());
    expect(state.undo().redo().score.toJson(), applied.toJson());
    final loaded = Score.fromJson(jsonDecode(jsonEncode(applied.toJson())));
    expect(loaded.reviewHistory.single.change, 'Assign sharp');
    expect(
      NotationReviewService.restore(
        loaded,
        loaded.reviewHistory.single,
      )!.toJson(),
      score.toJson(),
    );
    expect(marks(loaded).single.unassignedAccidental?.id, 'flat');
  });

  test('an already-correct note still resolves its mark and is undoable', () {
    final base = reviewScore();
    final score = base.replaceSymbolAt(
      0,
      0,
      0,
      base.parts.single.measures.first.notes.first.copyWith(alter: 1),
    );
    final issue = marks(score).first;
    final next = NotationReviewService.assignAccidental(score, issue, 0)!;
    expect(
      NotationReviewService.correction(
        score,
        next,
        issue,
        'Assign sharp',
      ).hasChanges,
      isTrue,
    );
  });

  test('unassigned metadata cannot affect music export or playback', () {
    final score = reviewScore();
    final original = MusicXmlExportService().toMusicXml(score);
    final parts = score.parts
        .map(
          (p) => p.copyWith(
            measures: p.measures
                .map((m) => m.copyWith(unassignedAccidentals: const []))
                .toList(),
          ),
        )
        .toList();
    expect(
      MusicXmlExportService().toMusicXml(score.copyWith(parts: parts)),
      original,
    );
    expect(
      const PlaybackConverter()
          .buildEvents(score)
          .where((e) => e.midiNote >= 0)
          .map((e) => e.midiNote),
      [60, 60, 60],
    );
    final changed = NotationReviewService.assignAccidental(
      score,
      marks(score).first,
      0,
    )!;
    expect(
      const PlaybackConverter()
          .buildEvents(changed)
          .where((e) => e.midiNote >= 0)
          .map((e) => e.midiNote),
      [61, 61, 60],
    );
    final xml = XmlDocument.parse(MusicXmlExportService().toMusicXml(changed));
    expect(xml.findAllElements('accidental').single.innerText, 'sharp');
  });

  test('photo evidence includes a mark even in a bar without notes', () async {
    final bar = const Measure(
      number: 1,
      symbols: [],
      unassignedAccidentals: [
        UnassignedAccidental(
          id: 'raw',
          alter: -1,
          source: SourceRegion(pageId: '', x: 20, y: 30, width: 10, height: 20),
        ),
      ],
    );
    final score = Score(
      id: 'mapped-score',
      title: '',
      composer: '',
      parts: [
        Part(id: 'p', name: '', measures: [bar]),
      ],
    );
    final attached = await ScoreSourceService.attach(
      score,
      Uint8List.fromList(img.encodePng(img.Image(width: 200, height: 100))),
      width: 200,
      height: 100,
    );
    final page = attached.sourcePages.single;
    final savedBar = attached.parts.single.measures.single;
    final mark = savedBar.unassignedAccidentals.single;
    expect(mark.id, '${page.id}:raw');
    expect(mark.source?.toJson(), {
      'pageId': page.id,
      'x': .1,
      'y': .3,
      'width': .05,
      'height': .2,
    });
    final crop = NotationReviewService.measureSource(savedBar)!;
    expect(crop.pageId, page.id);
    expect(crop.x, .1);
    expect(crop.width, closeTo(.05, 1e-10));
    expect(
      marks(Score.fromJson(jsonDecode(jsonEncode(attached.toJson())))),
      hasLength(1),
    );
  });
  test('attached pages namespace repeated mark ids and decisions', () async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 200, height: 100)),
    );
    Future<Score> attach() => ScoreSourceService.attach(
      reviewScore(),
      bytes,
      width: 200,
      height: 100,
    );
    final first = await attach();
    final second = await attach();
    final joined = first.appendScore(second);
    final issues = marks(joined);
    expect(issues, hasLength(4));
    expect(issues.map((i) => i.unassignedAccidental!.id).toSet(), hasLength(4));
    final kept = NotationReviewService.keep(joined, issues.first);
    expect(
      marks(Score.fromJson(jsonDecode(jsonEncode(kept.toJson())))),
      hasLength(3),
    );
    expect(joined.sourcePages, hasLength(2));
  });

  test(
    'marks without coordinates still receive a page-specific identity',
    () async {
      final original = reviewScore();
      final part = original.parts.single;
      final bar = part.measures.first;
      final attached = await ScoreSourceService.attach(
        original.copyWith(
          parts: [
            part.copyWith(
              measures: [
                bar.copyWith(
                  unassignedAccidentals: [
                    bar.unassignedAccidentals.first.copyWith(source: null),
                    bar.unassignedAccidentals.last,
                  ],
                ),
              ],
            ),
          ],
        ),
        Uint8List.fromList(img.encodePng(img.Image(width: 200, height: 100))),
        width: 200,
        height: 100,
      );
      final mark =
          attached.parts.single.measures.single.unassignedAccidentals.first;
      expect(mark.id, '${attached.sourcePages.single.id}:sharp');
      expect(mark.source, isNull);
    },
  );
}
