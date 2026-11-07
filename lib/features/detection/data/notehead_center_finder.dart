import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

/// Refines a known head end only when its ink contains one bounded solid blob.
/// Thin staff lines/stems, hollow ink and clipped/competing blobs keep the
/// original estimate. Association geometry is never changed by this helper.
class NoteheadCenterFinder {
  const NoteheadCenterFinder();

  Rect refine(img.Image image, {required Rect band, required Rect estimate}) {
    if (![
          band.left,
          band.top,
          band.right,
          band.bottom,
          estimate.height,
        ].every((v) => v.isFinite) ||
        band.isEmpty ||
        estimate.height <= 0 ||
        band.left < 0 ||
        band.top < 0 ||
        band.right > image.width ||
        band.bottom > image.height) {
      return estimate;
    }
    final left = band.left.floor(), top = band.top.floor();
    final width = band.right.ceil() - left;
    final height = band.bottom.ceil() - top;
    // A solid rectangle removes narrow stems and horizontal staff strokes.
    // Odd dimensions keep its centre on the same pixel at every scale.
    int odd(int value) => value.isEven ? value + 1 : value;
    final kw = odd(math.max(3, (band.width / 3).ceil()));
    final kh = odd(math.max(3, (estimate.height / 3).ceil()));
    if (width < kw + 1 || height < kh + 1) return estimate;

    final values = [
      for (var y = top; y < top + height; y++)
        for (var x = left; x < left + width; x++)
          (image.getPixel(x, y).luminanceNormalized * 255).round(),
    ];
    final sorted = [...values]..sort();
    final paper = sorted[(sorted.length - 1) * 9 ~/ 10];
    final limit = paper - math.max(18, paper * .15);
    final ink = [for (final value in values) value < limit];
    if (_hasHole(ink, width, height)) return estimate;

    final stride = width + 1;
    final sums = List<int>.filled(stride * (height + 1), 0);
    for (var y = 0; y < height; y++) {
      var row = 0;
      for (var x = 0; x < width; x++) {
        if (ink[y * width + x]) row++;
        sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row;
      }
    }
    final sw = width - kw + 1, sh = height - kh + 1;
    final support = List<bool>.filled(sw * sh, false);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        support[y * sw + x] =
            sums[(y + kh) * stride + x + kw] -
                sums[y * stride + x + kw] -
                sums[(y + kh) * stride + x] +
                sums[y * stride + x] ==
            kw * kh;
      }
    }

    final seen = List<bool>.filled(support.length, false);
    double? centre;
    for (var start = 0; start < support.length; start++) {
      if (!support[start] || seen[start]) continue;
      final todo = [start];
      seen[start] = true;
      var minX = start % sw, maxX = minX;
      var minY = start ~/ sw, maxY = minY;
      while (todo.isNotEmpty) {
        final next = todo.removeLast();
        final x = next % sw, y = next ~/ sw;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || nx >= sw || ny < 0 || ny >= sh) continue;
            final index = ny * sw + nx;
            if (support[index] && !seen[index]) {
              seen[index] = true;
              todo.add(index);
            }
          }
        }
      }
      final w = maxX - minX + 1, h = maxY - minY + 1;
      if (w < 2 ||
          h < 2 ||
          h > w ||
          minX == 0 ||
          minY == 0 ||
          maxX == sw - 1 ||
          maxY == sh - 1 ||
          !support[((minY + maxY) ~/ 2) * sw + (minX + maxX) ~/ 2]) {
        continue;
      }
      if (centre != null) return estimate;
      centre = top + (minY + maxY) / 2 + kh / 2;
    }
    if (centre == null) return estimate;
    return Rect.fromCenter(
      center: Offset(estimate.center.dx, centre),
      width: estimate.width,
      height: estimate.height,
    );
  }

  // Four-connected paper outside eight-connected ink. An enclosed light
  // pocket can be a hollow head or uncertain pencil fill; do not fit it.
  static bool _hasHole(List<bool> ink, int width, int height) {
    final seen = List<bool>.filled(ink.length, false);
    final todo = <int>[];
    var outside = 0;
    void add(int x, int y) {
      if (x < 0 || x >= width || y < 0 || y >= height) return;
      final index = y * width + x;
      if (!ink[index] && !seen[index]) {
        seen[index] = true;
        todo.add(index);
        outside++;
      }
    }

    for (var x = 0; x < width; x++) {
      add(x, 0);
      add(x, height - 1);
    }
    for (var y = 0; y < height; y++) {
      add(0, y);
      add(width - 1, y);
    }
    while (todo.isNotEmpty) {
      final next = todo.removeLast();
      final x = next % width, y = next ~/ width;
      add(x - 1, y);
      add(x + 1, y);
      add(x, y - 1);
      add(x, y + 1);
    }
    return outside < ink.where((dark) => !dark).length;
  }
}
