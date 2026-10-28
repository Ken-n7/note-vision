import '../models/note.dart';
import '../models/score.dart';

/// A note's place in the score.
typedef NotePosition = ({int part, int measure, int symbol});

/// Finds the notes that ties and slurs join.
class SpannerIndex {
  SpannerIndex(this.score) {
    for (final (p, part) in score.parts.indexed) {
      for (final (m, measure) in part.measures.indexed) {
        for (final (i, symbol) in measure.symbols.indexed) {
          if (symbol case Note(:final reviewId?)) {
            notes[reviewId] = (part: p, measure: m, symbol: i);
          }
        }
      }
    }
  }

  final Score score;

  /// Every note with a review ID.
  final notes = <String, NotePosition>{};

  Note noteAt(NotePosition p) =>
      score.parts[p.part].measures[p.measure].symbols[p.symbol] as Note;

  /// The spanners whose notes exist, the end after the start in the same
  /// part; a tie also needs the same staff position.
  List<(Spanner, NotePosition, NotePosition)> get live => [
    for (final spanner in score.spanners)
      if ((notes[spanner.from], notes[spanner.to]) case (
        final from?,
        final to?,
      ))
        if (from.part == to.part &&
            (from.measure, from.symbol).isBefore(to) &&
            (spanner.kind == SpannerKind.slur ||
                (noteAt(from).step, noteAt(from).octave) ==
                    (noteAt(to).step, noteAt(to).octave)))
          (spanner, from, to),
  ];
}

extension on (int, int) {
  bool isBefore(NotePosition other) =>
      $1 < other.measure || ($1 == other.measure && $2 < other.symbol);
}
