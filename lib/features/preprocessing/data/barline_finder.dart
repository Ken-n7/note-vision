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
///   * a stem lies inside the box the model drew around its note (clef
///     spines likewise inside the clef's box);
///   * a stem carries on above or below the staff, a barline stops at it.
///
/// Only barlines with a note or rest on both sides are kept: the line at a
/// staff's start or end splits nothing off.
///
// ponytail: tuned on the group's ≤1200 px phone photos; a barline drawn
// right against a note is taken for its stem and missed, which merges two
// bars. A barline class in the model would remove both limits.
class BarlineFinder {
  const BarlineFinder();

  /// Share of the rows between the outer lines that must be dark.
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
    return [
      for (final staff in staves) ..._onStaff(gray, staff, symbols),
    ];
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
        blockers.add(_fullBox(s) ?? box);
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
      var dark = 0;
      for (var y = t; y <= b; y++) {
        for (var d = -_reach; d <= _reach; d++) {
          if (gray.isDark(x + d, y)) {
            dark++;
            break;
          }
        }
      }
      cover[x] = dark / (b - t + 1);
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
        (r) => r.left - 1 <= cx && cx <= r.right + 1 && r.bottom > t && r.top < b,
      )) {
        continue;
      }
      final column = cx.round();
      final above = gray.darkShare(column - 1, column + 2, t - 1.4 * space, t - 0.6 * space);
      final below = gray.darkShare(column - 1, column + 2, b + 0.6 * space, b + 1.4 * space);
      if (math.max(above, below) > _maxBeyond) continue;
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
          for (var y = ty * _tile; y < math.min(height, (ty + 1) * _tile); y += 2)
            for (var x = tx * _tile; x < math.min(width, (tx + 1) * _tile); x += 2)
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
    return _pixels[y * width + x] <
        _limit[(y ~/ _tile) * _tilesX + x ~/ _tile];
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
