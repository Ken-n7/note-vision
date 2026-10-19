import 'package:flutter_test/flutter_test.dart';
import 'package:note_vision/core/models/barline_type.dart';
import 'package:note_vision/core/models/clef.dart';
import 'package:note_vision/core/models/key_signature.dart';
import 'package:note_vision/core/models/measure.dart';
import 'package:note_vision/core/models/note.dart';
import 'package:note_vision/core/models/part.dart';
import 'package:note_vision/core/models/rest.dart';
import 'package:note_vision/core/models/score.dart';
import 'package:note_vision/core/models/score_review.dart';
import 'package:note_vision/core/models/time_signature.dart';
import 'package:note_vision/features/editor/domain/editor_actions.dart';
import 'package:note_vision/features/editor/model/editor_state.dart';

void main() {
  const region = SourceRegion(
    pageId: 'scan',
    x: .1,
    y: .2,
    width: .3,
    height: .4,
  );
  final score = Score(
    id: 'clear',
    title: 'Study',
    composer: 'Composer',
    sourcePages: const [ScoreSourcePage(id: 'scan', imageBase64: 'evidence')],
    reviewHistory: [
      ScoreReviewEntry(
        id: 'decision',
        issueKey: 'issue',
        fingerprint: 'fingerprint',
        message: 'Kept',
        location: 'Measure 1',
        disposition: ReviewDisposition.kept,
        createdAt: DateTime.utc(2026),
      ),
    ],
    parts: const [
      Part(
        id: 'upper',
        name: 'Upper staff',
        measures: [
          Measure(
            number: 1,
            reviewId: 'm1',
            source: region,
            clef: Clef(sign: 'G', line: 2),
            keySignature: KeySignature(fifths: -2),
            timeSignature: TimeSignature(beats: 3, beatType: 4),
          leftBarlineType: BarlineType.repeatStart,
          rightBarlineType: BarlineType.repeatEnd,
            symbols: [
              Note(
                step: 'C',
                octave: 4,
                alter: 1,
                duration: 1,
                type: 'eighth',
                dots: 1,
                beamed: true,
                source: region,
              ),
              Rest(duration: 2, type: 'quarter'),
            ],
          ),
          Measure(
            number: 2,
            reviewId: 'm2',
            startsNewPage: true,
            startsNewSystem: true,
            symbols: [Note(step: 'G', octave: 4, duration: 2, type: 'quarter')],
          ),
        ],
      ),
      Part(
        id: 'lower',
        name: 'Lower staff',
        measures: [
          Measure(
            number: 1,
            clef: Clef(sign: 'F', line: 4),
            symbols: [Rest(duration: 8, type: 'whole')],
          ),
        ],
      ),
      Part(id: 'empty', name: 'Empty staff', measures: []),
    ],
  );

  test(
    'clears all pages and uneven parts, preserving metadata and evidence',
    () {
      final state = EditorState(
        score: score,
      ).selectSymbolAt(partIndex: 0, measureIndex: 1, symbolIndex: 0);
      expect(state.musicSymbolCount, 4);
      final cleared = state.clearAllSymbols();
      final expected = score.toJson();
      for (final part in expected['parts'] as List) {
        for (final measure in part['measures'] as List) {
          measure['symbols'] = [];
        }
      }
      expect(cleared.score.toJson(), expected);
      expect(cleared.musicSymbolCount, 0);
      expect(cleared.selectedPartIndex, 0);
      expect(cleared.selectedMeasureIndex, 1);
      expect(cleared.selectedSymbol, isNull);
      expect(cleared.selectedSymbolIndex, isNull);
      expect(cleared.hasUnsavedChanges, isTrue);
      expect(cleared.undoStack, hasLength(1));
      expect(score.parts.first.measures.first.symbols, hasLength(2));
      final restored = cleared.applyUndo();
      expect(restored.score, same(score));
      expect(restored.selectedSymbol, same(state.selectedSymbol));
      expect(restored.hasUnsavedChanges, isFalse);
      expect(restored.applyRedo().score.toJson(), expected);
      expect(cleared.insertNoteAfterSelection().hasEditableSelection, isTrue);
    },
  );

  test('preserves structural symbols stored in the symbols list', () {
    const clef = Clef(sign: 'G', line: 2);
    const key = KeySignature(fifths: 2);
    const meter = TimeSignature(beats: 4, beatType: 4);
    final state = EditorState(
      score: score.copyWith(
        parts: const [
          Part(
            id: 'p',
            name: 'Staff',
            measures: [
              Measure(
                number: 1,
                symbols: [
                  clef,
                  key,
                  meter,
                  Rest(duration: 2, type: 'quarter'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    expect(state.musicSymbolCount, 1);
    final cleared = state.clearAllSymbols();
    expect(cleared.score.parts.single.measures.single.symbols, [
      clef,
      key,
      meter,
    ]);
    expect(cleared.clearAllSymbols(), same(cleared));
  });

  test('empty scores do not change selection, history or saved state', () {
    for (final empty in [
      score.copyWith(parts: []),
      score.clearAllMusicSymbols(),
    ]) {
      final state = EditorState(score: empty);
      expect(state.clearAllSymbols(), same(state));
      expect(state.canUndo, isFalse);
      expect(state.hasUnsavedChanges, isFalse);
    }
  });

  test('clear replaces a redo branch and repeated clearing is a no-op', () {
    final edited = EditorState(score: score)
        .selectSymbolAt(partIndex: 0, measureIndex: 0, symbolIndex: 0)
        .moveSelectedSymbolUp();
    final undone = edited.applyUndo();
    expect(undone.canRedo, isTrue);
    final cleared = undone.clearAllSymbols();
    expect(cleared.canRedo, isFalse);
    expect(cleared.undoStack, hasLength(1));
    expect(cleared.clearAllSymbols(), same(cleared));
  });
}
