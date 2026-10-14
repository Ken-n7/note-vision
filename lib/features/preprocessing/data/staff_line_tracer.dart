import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import '../../detection/domain/detected_staff.dart';

/// Finds staves that are hand-ruled, sloped or bent by the paper, which the
/// straight-row projection misses.
///
///   1. Cut the page into narrow vertical strips. In each, a staff line shows
///      as a thin dark band that crosses the whole strip.
///   2. Follow each band from strip to strip into a line track. Staff lines
///      run most of the page; beams, stems and text do not.
///   3. Five neighbouring long tracks seen together make a candidate staff.
///   4. A clef picks the candidate it sits on ([staffAtClef]).
///
/// The result keeps each line where it really is (hand-ruled lines are
/// unevenly spaced) and how the staff rises and falls across the page
/// ([DetectedStaff.offsetAt]).
///
// ponytail: every length here is in pixels of the ≤1200 px image the picker
// hands over; scale them by image width if larger images are ever scanned.
class StaffLineTracer {
  const StaffLineTracer();

  /// Strip width. A 12 % slope moves a line 2 px across one strip.
  static const _strip = 16;

  /// Share of a strip's columns that must be dark on a line row.
  static const _minDarkShare = 0.55;

  /// Rows above and below used for the local paper brightness.
  static const _paperRows = 12;

  /// A band taller than this is a notehead or a beam, not a line.
  static const _maxBandRows = 9;

  /// Strips a track may miss (a note sitting on the line) before it ends.
  static const _maxSkip = 6;

  /// Strips a line may vanish under notes and still be the same line.
  static const _maxJoin = 16;

  /// Share of the page width a track must cover to count as a line piece.
  static const _minTrackShare = 0.15;

  /// Strips a run of five lines must be seen in to be a staff.
  static const _minSeen = 8;

  /// Narrowest line spacing considered, and the widest-to-narrowest gap ratio
  /// allowed inside one hand-ruled staff.
  static const _minSpacing = 4.2;
  static const _maxUneven = 3.2;

  /// The nearest line outside a staff must be at least this share of the
  /// staff's own widest gap away.
  static const _standsApart = 0.5;

  /// Strips right of its clef a staff may first be seen: the clef's own ink
  /// often hides the start of the lines.
  static const _lateStart = 40;

  /// Worst clef-to-staff mismatch accepted: spaces off centre plus 1.5 × the
  /// log of the size ratio.
  static const _maxCost = 2.6;

  // Measured on the group's own pages: a written G clef is 1.48 staves tall
  // and centred on the staff; an F clef is 0.85 staves tall with its middle
  // 0.2 spaces below the staff's. Printed proportions (1.75 and 0.75) do not
  // fit handwriting.
  static const gClefHeightInStaves = 1.48;
  static const fClefHeightInStaves = 0.85;
  static const fClefMiddleBelowStaffMiddle = 0.2;

  /// Every staff-like run of five lines on the page. Runs can overlap where
  /// staves are ruled close together; [staffAtClef] chooses between them.
  List<StaffCandidate> candidates(img.Image image) {
    final width = image.width, height = image.height;
    final n = math.max(1, width ~/ _strip);
    final gray = _luminance(image);

    final perStrip = [
      for (var j = 0; j < n; j++)
        _stripLines(gray, width, height, j * width ~/ n, (j + 1) * width ~/ n),
    ];
    final long = [
      for (final t in _joinPieces(_tracks(perStrip)))
        if (t.span >= _minTrackShare * n && t.points.length >= 0.5 * t.span) t,
    ];
    return _candidates(long, n, (j) => (j + 0.5) * width / n);
  }

  /// The candidate a clef sits on, as a staff named [id], or null when no
  /// candidate fits the clef's position and size.
  DetectedStaff? staffAtClef(
    List<StaffCandidate> candidates, {
    required bool isGClef,
    required Rect clef,
    required String id,
  }) => _bestAtClef(candidates, isGClef, clef)?.toStaff(id);

  static StaffCandidate? _bestAtClef(
    List<StaffCandidate> candidates,
    bool isGClef,
    Rect clef,
  ) {
    final x = clef.center.dx;
    StaffCandidate? best;
    var bestCost = _maxCost;
    for (final st in candidates) {
      if (st.xs.first - x > _lateStart * _strip || st.xs.last < x) continue;
      final spacing = st.height / 4;
      final wantMiddle = isGClef
          ? clef.center.dy
          : clef.center.dy - fClefMiddleBelowStaffMiddle * spacing;
      final wantHeight = clef.height /
          (isGClef ? gClefHeightInStaves : fClefHeightInStaves);
      final cost = (st.middleAt(x) - wantMiddle).abs() / spacing +
          1.5 * math.log(st.height / wantHeight).abs();
      if (cost < bestCost) {
        bestCost = cost;
        best = st;
      }
    }
    return best;
  }

  /// A clef box this many times taller than the page's typical clef is two
  /// stacked clefs the model boxed as one.
  static const _mergedClefHeight = 1.6;

  /// One staff per clef. A clef box that covers two stacked clefs gets every
  /// well-traced staff it lies across instead.
  List<DetectedStaff> stavesAtClefs(
    List<StaffCandidate> candidates,
    List<({bool isGClef, Rect box})> clefs,
  ) {
    if (clefs.isEmpty) return const [];
    final typicalHeight = _median([for (final c in clefs) c.box.height]);
    bool merged(Rect box) =>
        clefs.length >= 3 && box.height > _mergedClefHeight * typicalHeight;

    final chosen = <StaffCandidate>[];
    bool free(StaffCandidate c) => !chosen.any((o) => o.overlaps(c));

    for (final clef in clefs) {
      if (merged(clef.box)) continue;
      final best = _bestAtClef(candidates, clef.isGClef, clef.box);
      if (best != null && free(best)) chosen.add(best);
    }
    for (final clef in clefs) {
      if (!merged(clef.box)) continue;
      final x = clef.box.center.dx;
      // Most widely seen first: stray runs of lines are short-lived.
      final across = [
        for (final c in candidates)
          if (c.xs.first - x <= _lateStart * _strip &&
              c.xs.last >= x &&
              clef.box.top <= c.middleAt(x) &&
              c.middleAt(x) <= clef.box.bottom)
            c,
      ]..sort((a, b) => b.xs.length.compareTo(a.xs.length));
      for (final c in across) {
        if (free(c)) chosen.add(c);
      }
    }
    chosen.sort((a, b) => a.lines[0].compareTo(b.lines[0]));
    return [
      for (var i = 0; i < chosen.length; i++)
        chosen[i].toStaff('traced-staff-$i'),
    ];
  }

  static List<int> _luminance(img.Image image) {
    final out = List<int>.filled(image.width * image.height, 0);
    var i = 0;
    for (final p in image) {
      out[i++] = p.r.toInt();
    }
    return out;
  }

  /// Row centres of thin dark bands that cross the whole strip.
  static List<double> _stripLines(
    List<int> gray,
    int width,
    int height,
    int x0,
    int x1,
  ) {
    final w = x1 - x0;
    final mean = List<double>.filled(height, 0);
    for (var y = 0; y < height; y++) {
      var sum = 0;
      final row = y * width;
      for (var x = x0; x < x1; x++) {
        sum += gray[row + x];
      }
      mean[y] = sum / w;
    }
    // A pixel is ink when clearly darker than the paper near its row, taken
    // as the brightest row mean within reach. Lighting varies across a photo.
    final dark = List<bool>.filled(height * w, false);
    for (var y = 0; y < height; y++) {
      var paper = 0.0;
      final from = math.max(0, y - _paperRows);
      final to = math.min(height - 1, y + _paperRows);
      for (var k = from; k <= to; k++) {
        if (mean[k] > paper) paper = mean[k];
      }
      final limit = paper - math.max(18.0, 0.15 * paper);
      final row = y * width;
      for (var x = 0; x < w; x++) {
        dark[y * w + x] = gray[row + x0 + x] < limit;
      }
    }
    final out = <double>[];
    var start = -1;
    for (var y = 0; y <= height; y++) {
      var on = false;
      if (y < height) {
        // A sloped line sits a row higher on one side of the strip, so a
        // column counts when it is dark on this row or a neighbouring one.
        var count = 0;
        for (var x = 0; x < w; x++) {
          if (dark[y * w + x] ||
              (y > 0 && dark[(y - 1) * w + x]) ||
              (y + 1 < height && dark[(y + 1) * w + x])) {
            count++;
          }
        }
        on = count >= _minDarkShare * w;
      }
      if (on && start < 0) {
        start = y;
      } else if (!on && start >= 0) {
        if (y - start <= _maxBandRows) out.add((start + y - 1) / 2);
        start = -1;
      }
    }
    return out;
  }

  /// Links line rows of neighbouring strips into tracks.
  static List<_Track> _tracks(List<List<double>> perStrip) {
    final done = <_Track>[];
    var live = <_Track>[];
    for (var j = 0; j < perStrip.length; j++) {
      final ys = perStrip[j];
      final pairs = <(double, _Track, int)>[];
      for (final t in live) {
        final gap = j - t.lastStrip;
        final want = t.lastY + t.endSlope(4) * gap;
        final tolerance = 2.5 + 0.4 * (gap - 1);
        for (var k = 0; k < ys.length; k++) {
          final d = (ys[k] - want).abs();
          if (d <= tolerance) pairs.add((d, t, k));
        }
      }
      pairs.sort((a, b) => a.$1.compareTo(b.$1));
      final takenTracks = <_Track>{};
      final takenRows = <int>{};
      for (final (_, t, k) in pairs) {
        if (takenTracks.contains(t) || takenRows.contains(k)) continue;
        t.points.add((j, ys[k]));
        takenTracks.add(t);
        takenRows.add(k);
      }
      for (var k = 0; k < ys.length; k++) {
        if (!takenRows.contains(k)) live.add(_Track([(j, ys[k])]));
      }
      final keep = <_Track>[];
      for (final t in live) {
        (j - t.lastStrip < _maxSkip + 1 ? keep : done).add(t);
      }
      live = keep;
    }
    return [...done, ...live];
  }

  /// A line cut by a run of notes comes out as two tracks; joins pieces that
  /// continue each other.
  static List<_Track> _joinPieces(List<_Track> tracks) {
    final sorted = [...tracks]
      ..sort((a, b) => a.firstStrip.compareTo(b.firstStrip));
    final out = <_Track>[];
    for (final t in sorted) {
      _Track? best;
      var bestDistance = double.infinity;
      for (final o in out) {
        final gap = t.firstStrip - o.lastStrip;
        if (gap <= 0 || gap > _maxJoin) continue;
        final d = (t.points.first.$2 - (o.lastY + o.endSlope(5) * gap)).abs();
        if (d <= 3 + 0.3 * gap && d < bestDistance) {
          bestDistance = d;
          best = o;
        }
      }
      if (best != null) {
        best.points.addAll(t.points);
      } else {
        out.add(_Track([...t.points]));
      }
    }
    return out;
  }

  static List<StaffCandidate> _candidates(
    List<_Track> long,
    int n,
    double Function(int strip) centreX,
  ) {
    // Runs of five neighbouring lines, keyed by which tracks they are.
    final seen = <String, List<(int, List<double>)>>{};
    final keys = <String, List<int>>{};
    for (var j = 0; j < n; j++) {
      final all = <(double, int)>[
        for (var k = 0; k < long.length; k++)
          if (long[k].firstStrip <= j && j <= long[k].lastStrip)
            (long[k].yAt(j), k),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      // Two pieces of one line overlap for a strip or two.
      final here = <(double, int)>[];
      for (var i = 0; i < all.length; i++) {
        if (i == 0 || all[i].$1 - all[i - 1].$1 > 3) here.add(all[i]);
      }
      // Every run of five lines with plausible gaps, and how far it stands
      // apart: the nearest line outside it against its own widest gap. A
      // staff stands apart; four of its lines plus the nearest line of the
      // staff next to it do not. Where runs share lines, the one standing
      // furthest apart is the staff.
      final runs = <(double, int)>[];
      for (var i = 0; i + 5 <= here.length; i++) {
        var minGap = double.infinity, maxGap = 0.0;
        for (var k = i + 1; k < i + 5; k++) {
          final gap = here[k].$1 - here[k - 1].$1;
          if (gap < minGap) minGap = gap;
          if (gap > maxGap) maxGap = gap;
        }
        if (minGap < _minSpacing || maxGap > _maxUneven * minGap) continue;
        var outside = double.infinity;
        if (i > 0) outside = here[i].$1 - here[i - 1].$1;
        if (i + 5 < here.length) {
          outside = math.min(outside, here[i + 5].$1 - here[i + 4].$1);
        }
        if (outside < _standsApart * maxGap) continue;
        runs.add((outside / maxGap, i));
      }
      runs.sort((a, b) => b.$1.compareTo(a.$1));
      final taken = <int>{};
      for (final (_, i) in runs) {
        if ([for (var k = i; k < i + 5; k++) k].any(taken.contains)) continue;
        taken.addAll([for (var k = i; k < i + 5; k++) k]);
        final ids = [for (var k = i; k < i + 5; k++) here[k].$2];
        final key = ids.join(',');
        keys[key] = ids;
        (seen[key] ??= [])
            .add((j, [for (var k = i; k < i + 5; k++) here[k].$1]));
      }
    }

    // A line broken in two gives the same staff two different runs; they
    // still share most of their lines, in the same places.
    final names = keys.keys.toList();
    final parent = List<int>.generate(names.length, (i) => i);
    int find(int a) {
      while (parent[a] != a) {
        parent[a] = parent[parent[a]];
        a = parent[a];
      }
      return a;
    }

    for (var a = 0; a < names.length; a++) {
      for (var b = a + 1; b < names.length; b++) {
        final ka = keys[names[a]]!, kb = keys[names[b]]!;
        var same = 0;
        for (var i = 0; i < 5; i++) {
          if (ka[i] == kb[i]) same++;
        }
        if (same >= 3) parent[find(a)] = find(b);
      }
    }
    final groups = <int, List<(int, List<double>)>>{};
    for (var a = 0; a < names.length; a++) {
      (groups[find(a)] ??= []).addAll(seen[names[a]]!);
    }

    final out = <StaffCandidate>[];
    for (final sightings in groups.values) {
      if (sightings.length < _minSeen) continue;
      sightings.sort((a, b) => a.$1.compareTo(b.$1));
      final lines = [
        for (var i = 0; i < 5; i++)
          _median([for (final s in sightings) s.$2[i]]),
      ];
      var dys = [
        for (final s in sightings)
          [for (var i = 0; i < 5; i++) s.$2[i] - lines[i]]
                  .reduce((a, b) => a + b) /
              5,
      ];
      if (dys.length >= 3) {
        // One strip's reading can jump; a 3-wide median steadies it.
        dys = [
          dys.first,
          for (var k = 1; k < dys.length - 1; k++)
            _median([dys[k - 1], dys[k], dys[k + 1]]),
          dys.last,
        ];
      }
      out.add(StaffCandidate(
        lines: lines,
        xs: [for (final s in sightings) centreX(s.$1)],
        dys: dys,
      ));
    }
    // Where a staff is only partly traced, its lines and its neighbour's can
    // pass for one tall staff. A run that swallows a smaller staff is that.
    return [
      for (final c in out)
        if (!out.any((d) {
          final x = d.xs[d.xs.length ~/ 2];
          return d.height < 0.7 * c.height && c.spans(d.middleAt(x), x: x);
        }))
          c,
    ];
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Five lines seen running together across part of the page.
class StaffCandidate {
  const StaffCandidate({
    required this.lines,
    required this.xs,
    required this.dys,
  });

  /// Typical height of each of the five lines, top to bottom.
  final List<double> lines;

  /// Columns where the staff was seen, and how far below [lines] it sat.
  final List<double> xs;
  final List<double> dys;

  double get height => lines[4] - lines[0];

  double offsetAt(double x) => toStaff('').offsetAt(x);

  /// Height of the middle of the staff at column [x].
  double middleAt(double x) => (lines[0] + lines[4]) / 2 + offsetAt(x);

  /// True when [y] lies between the outer lines at column [x].
  bool spans(double y, {required double x}) {
    final level = y - offsetAt(x);
    return level >= lines[0] && level <= lines[4];
  }

  /// True when the two share more than a quarter of the smaller one's
  /// height, measured where both were seen.
  bool overlaps(StaffCandidate other) {
    final from = math.max(xs.first, other.xs.first);
    final to = math.min(xs.last, other.xs.last);
    final x = (from + to) / 2;
    final top = math.max(lines[0] + offsetAt(x), other.lines[0] + other.offsetAt(x));
    final bottom =
        math.min(lines[4] + offsetAt(x), other.lines[4] + other.offsetAt(x));
    return bottom - top > 0.25 * math.min(height, other.height);
  }

  DetectedStaff toStaff(String id) {
    final space = (lines[4] - lines[0]) / 4;
    return DetectedStaff(
      id: id,
      topY: lines[0] - space,
      bottomY: lines[4] + space,
      lineYs: lines,
      offsetXs: xs,
      offsetYs: dys,
    );
  }
}

/// One staff line followed across strips: (strip index, row) points.
class _Track {
  _Track(this.points);

  final List<(int, double)> points;

  int get firstStrip => points.first.$1;
  int get lastStrip => points.last.$1;
  double get lastY => points.last.$2;
  int get span => lastStrip - firstStrip + 1;

  /// Slope over the last [back] points, steadier than the last two alone.
  double endSlope(int back) {
    final from = points[math.max(0, points.length - 1 - back)];
    final to = points.last;
    return to.$1 > from.$1 ? (to.$2 - from.$2) / (to.$1 - from.$1) : 0;
  }

  /// Row of the line at [strip], which must lie within the track.
  double yAt(int strip) {
    var lo = 0, hi = points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (points[mid].$1 <= strip) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = points[lo], b = points[hi];
    if (b.$1 == a.$1) return a.$2;
    return a.$2 + (b.$2 - a.$2) * (strip - a.$1) / (b.$1 - a.$1);
  }
}
