import '../../models/articulation.dart';

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
