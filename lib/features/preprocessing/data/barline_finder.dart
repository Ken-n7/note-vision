import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

import '../../detection/domain/detected_barline.dart';
import '../../detection/domain/detected_staff.dart';
import '../../detection/domain/detected_symbol.dart';

/// Finds the barlines drawn on each staff, so bars follow the page instead
/// of being filled by counting beats. The model has no barline class.
///
/// A barline is a thin dark stroke that runs from a staff's top line to its
/// bottom line, as the staff runs there. Stems look the same; what tells
/// them apart:
///   * connected head/stem ink inside a note box, or an attached head on a
///     missed note, identifies a stem (clef spines stay inside clef boxes);
///   * a stem carries on above or below the staff, a barline stops at it.
///
/// Only barlines with a note or rest on both sides are kept: the line at a
/// staff's start or end splits nothing off.
///
/// A barline physically joined to a note can still be ambiguous. Keep these
/// geometry checks independent of the model's confidence/value thresholds.
class BarlineFinder {
  const BarlineFinder();

  /// Share of non-staff-line rows between the outer lines that must be dark.
  static const _minCover = 0.8;

  /// Columns either side a row may be dark in: hand-drawn barlines lean.
  static const _reach = 2;

  /// Widest stroke, in staff spaces, still taken for a line.
  static const _maxWidth = 0.9;

  /// Strokes closer than this, in staff spaces, are one (double) barline.
  static const _merge = 0.8;

  /// Share of the column just above or below the staff that, when dark,
  /// shows the stroke carries on past the staff.
  static const _maxBeyond = 0.6;

  List<DetectedBarline> find(
    img.Image image,
    List<DetectedStaff> staves,
    List<DetectedSymbol> symbols,
  ) {
    final gray = _Gray(image);
    return [for (final staff in staves) ..._onStaff(gray, staff, symbols)];
  }

  List<DetectedBarline> _onStaff(
    _Gray gray,
    DetectedStaff staff,
    List<DetectedSymbol> symbols,
  ) {
    if (staff.lineYs.length < 5) return const [];
    final top0 = staff.lineYs.first, bottom0 = staff.lineYs.last;
    final space = (bottom0 - top0) / 4;
    if (space < 4) return const [];

    // Boxes a stroke may belong to, and the notes and rests on this staff.
    final blockers = <Rect>[];
    final musicXs = <double>[];
    for (final s in symbols) {
      final kind = s.musicSymbol;
      final box = s.boundingBox;
      if (kind == null || box == null) continue;
      final level = box.center.dy - staff.offsetAt(box.center.dx);
      if (level < top0 - 2.5 * space || level > bottom0 + 2.5 * space) {
        continue;
      }
      if (kind.isNote || kind.isRest) musicXs.add(box.center.dx);
      if (kind.isClef) blockers.add(box);
      if (kind.isNote && s.metadata?['noteType'] != 'whole') {
        blockers.addAll(_noteBlockers(gray, staff, s, space));
      }
    }
    if (musicXs.length < 2) return const [];

    final xs = staff.offsetXs;
    final from = math.max(
      _reach,
      xs.isEmpty ? 0 : (xs.first - 3 * space).floor(),
    );
    final to = math.min(
      gray.width - _reach - 1,
      xs.isEmpty ? gray.width : (xs.last + 3 * space).ceil(),
    );

    int topAt(int x) => (top0 + staff.offsetAt(x.toDouble())).round();
    int bottomAt(int x) => (bottom0 + staff.offsetAt(x.toDouble())).round();

    final cover = List<double>.filled(to + 1, 0);
    for (var x = from; x <= to; x++) {
      final t = topAt(x), b = bottomAt(x);
      if (t < 0 || b >= gray.height) continue;
      var dark = 0, rows = 0;
      for (var y = t; y <= b; y++) {
        // Staff lines are dark at every column. Counting them as support
        // promoted short note stems to barlines when their head was missed.
        if (_staffRow(staff, x.toDouble(), y, space)) continue;
        rows++;
        for (var d = -_reach; d <= _reach; d++) {
          if (gray.isDark(x + d, y)) {
            dark++;
            break;
          }
        }
      }
      cover[x] = rows == 0 ? 0 : dark / rows;
    }

    final found = <double>[];
    var x = from;
    while (x <= to) {
      if (cover[x] < _minCover) {
        x++;
        continue;
      }
      var end = x;
      while (end + 1 <= to && cover[end + 1] >= _minCover) {
        end++;
      }
      final cx = (x + end) / 2;
      final width = end - x + 1 - 2 * _reach;
      x = end + 1;
      if (width > _maxWidth * space) continue;

      final t = top0 + staff.offsetAt(cx), b = bottom0 + staff.offsetAt(cx);
      if (blockers.any(
        (r) =>
            r.left - 1 <= cx && cx <= r.right + 1 && r.bottom > t && r.top < b,
      )) {
        continue;
      }
      final column = cx.round();
      final above = gray.darkShare(
        column - 1,
        column + 2,
        t - 1.4 * space,
        t - 0.6 * space,
      );
      final below = gray.darkShare(
        column - 1,
        column + 2,
        b + 0.6 * space,
        b + 1.4 * space,
      );
      if (math.max(above, below) > _maxBeyond) continue;
      // A missed detection has no note box to veto its stem. Look for a
      // bounded head/flag attached to this stroke, ignoring horizontal staff
      // ink. An independent adjacent barline has no such side branch.
      if (_hasHead(gray, staff, column, t, b, space, math.max(1, width))) {
        continue;
      }
      found.add(cx);
    }

    final merged = <double>[];
    for (final cx in found) {
      if (merged.isNotEmpty && cx - merged.last < _merge * space) {
        merged[merged.length - 1] = (merged.last + cx) / 2;
      } else {
        merged.add(cx);
      }
    }

    return [
      for (final cx in merged)
        if (musicXs.any((m) => m < cx) && musicXs.any((m) => m > cx))
          DetectedBarline(x: cx, staffId: staff.id),
    ];
  }

  static Rect? _fullBox(DetectedSymbol symbol) {
    final full = symbol.metadata?[DetectedSymbol.fullBoxKey];
    if (full is! List || full.length != 4) return null;
    final v = [for (final e in full) (e as num).toDouble()];
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }

  static bool _staffRow(DetectedStaff staff, double x, int y, double space) {
    final shift = staff.offsetAt(x);
    final radius = math.min(_reach.toDouble(), space / 4);
    return staff.lineYs.any((line) => (y - line - shift).abs() <= radius);
  }

  /// A loose whole-symbol box can contain both a note and an independent
  /// barline. Trace connected head/stem ink by row, excluding horizontal
  /// staff ink. This also follows a slanted stem without covering a separate
  /// stroke alongside it. Insufficient evidence retains the original box.
  static List<Rect> _noteBlockers(
    _Gray gray,
    DetectedStaff staff,
    DetectedSymbol symbol,
    double space,
  ) {
    final head = symbol.boundingBox!;
    final full = _fullBox(symbol);
    if (full == null) return [head];
    final x0 = math.max(0, full.left.floor());
    final x1 = math.min(gray.width - 1, full.right.ceil());
    int? seedY, seedLeft, seedRight;
    var best = 2 * _reach;
    for (
      var y = math.max(0, full.top.floor());
      y < math.min(gray.height, full.bottom.ceil());
      y++
    ) {
      // The head localizer can mistake a flag for the head. Both ends of
      // the whole-symbol box can anchor its connected ink.
      if (y > full.top + full.height * .3 &&
          y < full.bottom - full.height * .3) {
        continue;
      }
      var x = x0;
      while (x <= x1) {
        if (_staffRow(staff, x.toDouble(), y, space) || !gray.isDark(x, y)) {
          x++;
          continue;
        }
        final start = x++;
        while (x <= x1 &&
            !_staffRow(staff, x.toDouble(), y, space) &&
            gray.isDark(x, y)) {
          x++;
        }
        // Clipped or very long runs can be staff ink continuing outside
        // the box, rather than the note's bounded head.
        final width = x - start;
        if (start == x0 || x > x1 || width <= best || width > 1.5 * space) {
          continue;
        }
        best = width;
        seedY = y;
        seedLeft = start;
        seedRight = x - 1;
      }
    }
    if (seedY == null) return [full];
    final ink = <Rect>[
      Rect.fromLTRB(
        seedLeft!.toDouble(),
        seedY.toDouble(),
        seedRight!.toDouble(),
        seedY + 1.0,
      ),
    ];
    var minY = seedY, maxY = seedY;
    for (final direction in [-1, 1]) {
      var left = seedLeft, right = seedRight, gaps = 0;
      for (
        var y = seedY + direction;
        y >= math.max(0, full.top.floor()) &&
            y < math.min(gray.height, full.bottom.ceil());
        y += direction
      ) {
        final from = math.max(x0, left - _reach),
            to = math.min(x1, right + _reach);
        int? nextLeft, nextRight;
        var staffOnly = true;
        for (var x = from; x <= to; x++) {
          if (_staffRow(staff, x.toDouble(), y, space)) continue;
          staffOnly = false;
          if (!gray.isDark(x, y)) continue;
          nextLeft ??= x;
          nextRight = x;
        }
        if (staffOnly) continue;
        if (nextLeft == null) {
          if (++gaps > _reach) break;
          continue;
        }
        gaps = 0;
        left = nextLeft;
        right = nextRight!;
        ink.add(
          Rect.fromLTRB(
            left.toDouble(),
            y.toDouble(),
            right.toDouble(),
            y + 1.0,
          ),
        );
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    // A disconnected dot or flag alone is insufficient evidence to relax
    // the original whole-symbol veto.
    return maxY - minY + 1 < full.height / 2 ? [full] : ink;
  }

  static bool _hasHead(
    _Gray gray,
    DetectedStaff staff,
    int x,
    double top,
    double bottom,
    double space,
    int strokeWidth,
  ) {
    final reach = (2 * space).ceil();
    var broadRows = 0, lastBroad = -2;
    for (
      var y = math.max(0, top.floor());
      y <= math.min(gray.height - 1, bottom.ceil());
      y++
    ) {
      if (_staffRow(staff, x.toDouble(), y, space)) continue;
      int? ink;
      for (var distance = 0; distance <= _reach && ink == null; distance++) {
        if (gray.isDark(x - distance, y)) {
          ink = x - distance;
        } else if (gray.isDark(x + distance, y)) {
          ink = x + distance;
        }
      }
      if (ink == null) continue;
      var left = ink, right = ink;
      while (left > 0 && ink - left < reach && gray.isDark(left - 1, y)) {
        left--;
      }
      while (right < gray.width - 1 &&
          right - ink < reach &&
          gray.isDark(right + 1, y)) {
        right++;
      }
      // Long horizontal strokes are staff lines or beams, not a head.
      if (ink - left >= reach || right - ink >= reach) continue;
      final width = right - left + 1;
      if (width > strokeWidth + 2 * _reach && width <= 1.5 * space) {
        broadRows = lastBroad == y - 1 ? broadRows + 1 : 1;
        lastBroad = y;
        if (broadRows >= _reach + 1) return true;
      }
    }
    return false;
  }
}

/// Luminance with a local paper level, so ink reads as dark under uneven
/// light.
class _Gray {
  _Gray(img.Image image)
    : width = image.width,
      height = image.height,
      _pixels = List<int>.filled(image.width * image.height, 0) {
    var i = 0;
    for (final p in image) {
      _pixels[i++] = p.r.toInt();
    }
    // Paper level per tile: the 90th percentile of its pixels.
    _tilesX = (width + _tile - 1) ~/ _tile;
    final tilesY = (height + _tile - 1) ~/ _tile;
    _limit = List<double>.filled(_tilesX * tilesY, 0);
    for (var ty = 0; ty < tilesY; ty++) {
      for (var tx = 0; tx < _tilesX; tx++) {
        final values = <int>[
          for (
            var y = ty * _tile;
            y < math.min(height, (ty + 1) * _tile);
            y += 2
          )
            for (
              var x = tx * _tile;
              x < math.min(width, (tx + 1) * _tile);
              x += 2
            )
              _pixels[y * width + x],
        ]..sort();
        final paper = values.isEmpty
            ? 255.0
            : values[(values.length * 0.9).floor().clamp(0, values.length - 1)]
                  .toDouble();
        _limit[ty * _tilesX + tx] = paper - math.max(18.0, 0.15 * paper);
      }
    }
  }

  static const _tile = 48;

  final int width;
  final int height;
  final List<int> _pixels;
  late final int _tilesX;
  late final List<double> _limit;

  bool isDark(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return _pixels[y * width + x] < _limit[(y ~/ _tile) * _tilesX + x ~/ _tile];
  }

  double darkShare(int x0, int x1, double y0, double y1) {
    final top = math.max(0, y0.floor()), bottom = math.min(height, y1.ceil());
    var dark = 0, all = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = x0; x < x1; x++) {
        all++;
        if (isDark(x, y)) dark++;
      }
    }
    return all == 0 ? 0 : dark / all;
  }
}
