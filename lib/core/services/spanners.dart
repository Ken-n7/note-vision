import '../models/note.dart';
import '../models/rest.dart';
import '../models/score.dart';

/// A note's place in the score.
typedef NotePosition = ({int part, int measure, int symbol});

/// Finds the notes that ties and slurs join.
class SpannerIndex {
  SpannerIndex(this.score) {
    for (final (p, part) in score.parts.indexed) {
      for (final (m, measure) in part.measures.indexed) {
        for (final (i, symbol) in measure.symbols.indexed) {
          if (symbol case Note(:final reviewId?) || Rest(:final reviewId?)) {
            notes[reviewId] = (part: p, measure: m, symbol: i);
          }
        }
      }
    }
  }

  final Score score;

  /// Every note and rest with a review ID.
  final notes = <String, NotePosition>{};

  Note? noteAt(NotePosition p) => switch (score
      .parts[p.part]
      .measures[p.measure]
      .symbols[p.symbol]) {
    final Note n => n,
    _ => null,
  };

  /// The spanners whose notes exist, the end after the start in the same
  /// part (a hairpin may start and end on one note); a tie also needs the
  /// same staff position.
  List<(Spanner, NotePosition, NotePosition)> get live => [
    for (final spanner in score.spanners)
      if ((notes[spanner.from], notes[spanner.to]) case (
        final from?,
        final to?,
      ))
        if (from.part == to.part &&
            ((from.measure, from.symbol).isBefore(to) ||
                (from == to && spanner.kind.isHairpin)) &&
            (spanner.kind != SpannerKind.tie ||
                _samePosition(noteAt(from), noteAt(to))))
          (spanner, from, to),
  ];
}

bool _samePosition(Note? a, Note? b) =>
    a != null && b != null && (a.step, a.octave) == (b.step, b.octave);

extension on (int, int) {
  bool isBefore(NotePosition other) =>
      $1 < other.measure || ($1 == other.measure && $2 < other.symbol);
}
