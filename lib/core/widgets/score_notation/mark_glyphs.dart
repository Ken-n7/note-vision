import '../../models/articulation.dart';
import '../../models/barline_type.dart';
import '../../models/navigation_mark.dart';

/// A shape of an articulation or ornament, in editor pixels relative to the
/// notehead with y pointing down. The editor and the PDF draw the same
/// shapes (the PDF scales them and flips y).
sealed class MarkShape {
  const MarkShape();
}

class MarkDot extends MarkShape {
  const MarkDot(this.x, this.y, this.radius);
  final double x, y, radius;
}

/// Straight segments through [points]; [filled] closes and fills them.
class MarkLines extends MarkShape {
  const MarkLines(this.points, {this.width = 1.4, this.filled = false});
  final List<(double, double)> points;
  final double width;
  final bool filled;
}

/// Cubic curves from [start]; each segment is (c1, c2, end).
class MarkCurve extends MarkShape {
  const MarkCurve(
    this.start,
    this.segments, {
    this.width = 1.5,
    this.filled = false,
  });
  final (double, double) start;
  final List<((double, double), (double, double), (double, double))> segments;
  final double width;
  final bool filled;
}

class MarkText extends MarkShape {
  const MarkText(this.text, this.x, this.y, this.size);
  final String text;
  final double x, y, size;
}

/// The shapes for [marks] on one note. Marks that belong next to the head
/// (staccato, tenuto, accents) go on the side away from the stem, nearest
/// first; ornaments and fermatas go above the staff and the stem.
/// [staffTop] is the top line's y relative to the head; [stemReach] is how
/// far the note reaches above its head.
List<MarkShape> markShapes(
  List<Articulation> marks, {
  required bool stemUp,
  required double staffTop,
  required double stemReach,
}) {
  final shapes = <MarkShape>[];
  final side = stemUp ? 1.0 : -1.0;
  var distance = 10.0;
  for (final mark in [
    for (final m in marks)
      if (m == Articulation.staccato ||
          m == Articulation.staccatissimo ||
          m == Articulation.tenuto)
        m,
    for (final m in marks)
      if (m == Articulation.accent || m == Articulation.marcato) m,
  ]) {
    final y = side * distance;
    shapes.addAll(switch (mark) {
      Articulation.staccato => [MarkDot(0, y, 1.9)],
      // A wedge pointing at the head.
      Articulation.staccatissimo => [
        MarkLines([
          (-2.2, y + 3 * side),
          (2.2, y + 3 * side),
          (0, y - 3 * side),
        ], filled: true),
      ],
      Articulation.tenuto => [
        MarkLines([(-5, y), (5, y)], width: 1.6),
      ],
      Articulation.accent => [
        MarkLines([(-5, y - 3.2), (5, y), (-5, y + 3.2)], width: 1.3),
      ],
      // Points away from the head: up above it, down below it.
      _ => [
        MarkLines([
          (-4, y - 4 * side),
          (0, y + 4 * side),
          (4, y - 4 * side),
        ], width: 1.6),
      ],
    });
    distance += 8;
  }
  var top = (staffTop < -stemReach ? staffTop : -stemReach) - 9;
  for (final mark in marks.where((m) => !m.nearHead)) {
    final y = top;
    shapes.addAll(switch (mark) {
      Articulation.fermata => [
        // An arch, thick at the top, over a dot.
        MarkCurve(
          (-7, y + 3),
          [
            ((-7, y - 8), (7, y - 8), (7, y + 3)),
            ((5.5, y + 3), (3, y - 2), (0, y - 2)),
            ((-3, y - 2), (-5.5, y + 3), (-7, y + 3)),
          ],
          filled: true,
        ),
        MarkDot(0, y + 1.5, 1.4),
      ],
      Articulation.trill => [MarkText('tr', 0, y, 12)],
      Articulation.turn => [
        MarkCurve(
          (-7, y),
          [
            ((-7, y - 5), (-2, y - 5), (0, y)),
            ((2, y + 5), (7, y + 5), (7, y)),
          ],
          width: 1.6,
        ),
      ],
      _ => [
        MarkLines([
          (-7, y + 1),
          (-4, y - 2),
          (-1, y + 2),
          (2, y - 2),
          (5, y + 2),
          (7, y - 1),
        ], width: 1.5),
        // A mordent has a stroke through it; an inverted mordent does not.
        if (mark == Articulation.mordent)
          MarkLines([(0, y - 5), (0, y + 5)], width: 1.2),
      ],
    });
    top -= 12;
  }
  return shapes;
}

/// A bar's repeat and barline signs, ending bracket and navigation, in
/// editor pixels relative to the bar's left edge on the top staff line, y
/// down. [width] is the bar's width and [spacing] the staff line spacing.
/// [ending] is the ending this bar belongs to (its label shown where it
/// starts); [first] draws endings and navigation, which only the top staff
/// of a system shows.
List<MarkShape> barShapes({
  required double width,
  required double spacing,
  BarlineType? left,
  BarlineType? right,
  ({String? label, bool closes})? ending,
  List<NavigationMark> navigation = const [],
  bool first = true,
}) {
  final height = spacing * 4;
  final shapes = <MarkShape>[];
  // Middle two spaces hold a repeat's dots.
  List<MarkShape> dots(double x) => [
    MarkDot(x, spacing * 1.5, 1.8),
    MarkDot(x, spacing * 2.5, 1.8),
  ];
  MarkShape line(double x, double w) =>
      MarkLines([(x, 0), (x, height)], width: w);
  switch (left) {
    case BarlineType.repeatStart:
      shapes
        ..add(line(1.5, 3))
        ..add(line(5, 1))
        ..addAll(dots(9));
    default:
  }
  switch (right) {
    case BarlineType.repeatEnd:
      shapes
        ..add(line(width - 1.5, 3))
        ..add(line(width - 5, 1))
        ..addAll(dots(width - 9));
    case BarlineType.finalBar:
      shapes
        ..add(line(width - 1.5, 3))
        ..add(line(width - 5, 1));
    case BarlineType.doubleBar:
      shapes
        ..add(line(width, 1))
        ..add(line(width - 3.5, 1));
    default:
  }
  if (!first) return shapes;
  if (ending != null) {
    // Above the bar number.
    const y = -30.0;
    final x1 = ending.label == null ? 0.0 : 3.0;
    final x2 = width - 3;
    shapes.add(
      MarkLines([
        if (ending.label != null) (x1, y + 9),
        (x1, y),
        (x2, y),
        if (ending.closes) (x2, y + 9),
      ], width: 1),
    );
    if (ending.label case final label?) {
      // Clear of the bar number under the hook.
      shapes.add(MarkText(label, x1 + 14 + label.length * 2.8, y + 8, 10));
    }
  }
  // Signs at the bar's start go above its number; words end at its end.
  var start = -28.0, end = -14.0;
  for (final mark in navigation) {
    final above = mark.atEnd ? end : start;
    switch (mark) {
      case NavigationMark.segno:
        shapes.addAll([
          MarkText('S', 8, above, 16),
          MarkLines([(2, above + 6), (14, above - 6)], width: 1.2),
          MarkDot(4, above - 2, 1.4),
          MarkDot(12, above + 2, 1.4),
        ]);
      case NavigationMark.coda:
        shapes.addAll([
          MarkCurve(
            (8, above - 5),
            [
              ((12, above - 5), (12, above + 5), (8, above + 5)),
              ((4, above + 5), (4, above - 5), (8, above - 5)),
            ],
            width: 1.4,
          ),
          MarkLines([(8, above - 8), (8, above + 8)], width: 1.2),
          MarkLines([(1, above), (15, above)], width: 1.2),
        ]);
      default:
        // Words end at the bar line.
        final x = width - mark.text.length * 3.2 - 4;
        shapes.add(MarkText(mark.text, x, above, 11));
    }
    if (mark.atEnd) {
      end -= 14;
    } else {
      start -= 18;
    }
  }
  return shapes;
}
