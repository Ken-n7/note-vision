import 'dart:math' as math;

import '../../models/clef.dart';
import '../../models/key_signature.dart';
import '../../models/measure.dart';
import '../../models/note.dart';
import '../../models/rest.dart';
import '../../models/score.dart';
import '../../models/time_signature.dart';

typedef ScoreCell = ({int part, int measure});

/// Presentation coordinates only: the saved score retains every original part.
class ScoreDisplayProjection {
  ScoreDisplayProjection._(
    this.source,
    this.score,
    this.columns,
    this.origins,
    this.hiddenMeasures,
    this.rowsPerPage,
  );

  final Score source, score;
  final int columns, rowsPerPage;
  final List<ScoreCell?>? origins;
  final Set<int> hiddenMeasures;
  bool get sequential => origins != null;
  late final _indices = <ScoreCell, int>{
    if (origins != null)
      for (final (i, cell) in origins!.indexed) ?cell: i,
  };

  int index(int part, int measure) =>
      sequential ? _indices[(part: part, measure: measure)] ?? -1 : measure;
  int part(int originalPart) => sequential ? 0 : originalPart;
  ScoreCell? origin(int part, int measure) => sequential
      ? (measure < 0 ? null : origins!.elementAtOrNull(measure))
      : (part: part, measure: measure);

  static final _cache = Expando<ScoreDisplayProjection>();
  static final _displayScores = Expando<ScoreDisplayProjection>();
  static final _independentRows = Expando<bool>();
  static bool beginsIndependentRow(Measure measure) =>
      _independentRows[measure] == true;
  static void copyRowContext(Measure from, Measure to) {
    if (beginsIndependentRow(from)) _independentRows[to] = true;
  }

  static ScoreDisplayProjection? fromDisplayScore(Score? score) =>
      score == null ? null : _displayScores[score];
  static ScoreDisplayProjection forScore(Score score) =>
      _cache[score] ??= _build(score);

  static bool _isScan(Score score) =>
      score.playbackLayout == ScorePlaybackLayout.sequentialStaves &&
      score.musicXmlSource == null &&
      score.parts.length > 1 &&
      score.parts.every(
        (p) =>
            !p.joinsPrevious &&
            !p.isTab &&
            !p.isPercussion &&
            p.staffLines == 5,
      ) &&
      (score.id == 'mapped-score' ||
          score.sourcePages.isNotEmpty ||
          score.parts.any(
            (p) => p.measures.any(
              (m) =>
                  m.source != null ||
                  m.symbols.any(
                    (s) => switch (s) {
                      Note(:final source) ||
                      Rest(:final source) => source != null,
                      _ => false,
                    },
                  ),
            ),
          ));

  static ScoreDisplayProjection _build(Score original) {
    if (!_isScan(original)) {
      return ScoreDisplayProjection._(original, original, 0, null, const {}, 0);
    }
    final columns = original.parts.fold(
      1,
      (n, p) => math.max(n, math.min(4, p.measures.length)),
    );
    final cells = <ScoreCell?>[];
    final hidden = <int>{};
    final measures = <Measure>[];
    String? lastPage;
    var rows = 0, groupRows = 0, largestGroup = 0;
    for (final (p, part) in original.parts.indexed) {
      Clef? clef = const Clef(sign: 'G', line: 2);
      KeySignature? key;
      TimeSignature? meter;
      var column = 0;
      void pad() {
        while (column > 0 && column < columns) {
          hidden.add(measures.length);
          measures.add(const Measure(number: 0, symbols: []));
          cells.add(null);
          column++;
        }
        column = 0;
      }

      for (final (m, measure) in part.measures.indexed) {
        clef = measure.clef ?? clef;
        key = measure.keySignature ?? key;
        meter = measure.timeSignature ?? meter;
        final page =
            measure.source?.pageId ??
            measure.symbols
                .map(
                  (s) => switch (s) {
                    Note(:final source) ||
                    Rest(:final source) => source?.pageId,
                    _ => null,
                  },
                )
                .whereType<String>()
                .firstOrNull;
        final newPage =
            measure.startsNewPage ||
            (page != null &&
                page.isNotEmpty &&
                lastPage != null &&
                page != lastPage);
        if (newPage || measure.startsNewSystem) pad();
        if (newPage) {
          largestGroup = math.max(largestGroup, groupRows);
          groupRows = 0;
        }
        if (column == 0) {
          rows++;
          groupRows++;
        }
        final rendered = measure.copyWith(
          clef: clef,
          keySignature: key,
          timeSignature: meter,
          startsNewPage: newPage,
        );
        if (m == 0) _independentRows[rendered] = true;
        measures.add(rendered);
        cells.add((part: p, measure: m));
        column = (column + 1) % columns;
        if (page?.isNotEmpty == true) lastPage = page;
      }
      pad();
    }
    largestGroup = math.max(largestGroup, groupRows);
    final perPage = lastPage == null
        ? math.min(8, math.max(1, rows))
        : math.max(1, largestGroup);
    final display = ScoreDisplayProjection._(
      original,
      original.copyWith(
        parts: [
          original.parts.first.copyWith(measures: List.unmodifiable(measures)),
        ],
      ),
      columns,
      List.unmodifiable(cells),
      Set.unmodifiable(hidden),
      perPage,
    );
    _displayScores[display.score] = display;
    return display;
  }
}
