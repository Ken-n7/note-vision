import 'package:flutter/foundation.dart';

class DetectedStaff {
  final String id;
  final double topY;
  final double bottomY;
  final List<double> lineYs;

  /// How far the staff sits below [lineYs] at the columns [offsetXs]. A
  /// hand-drawn or photographed staff slopes and bends; [lineYs], [topY] and
  /// [bottomY] hold its typical height and these samples carry the bend.
  /// Empty for a level staff.
  final List<double> offsetXs;
  final List<double> offsetYs;

  const DetectedStaff({
    required this.id,
    required this.topY,
    required this.bottomY,
    required this.lineYs,
    this.offsetXs = const [],
    this.offsetYs = const [],
  });

  /// Sightings used for the slope a staff keeps past its two ends.
  static const _endFit = 12;

  /// Vertical shift of the whole staff at column [x]: line `i` runs through
  /// `lineYs[i] + offsetAt(x)`. Past its first or last sample the staff
  /// carries on at the slope it had there.
  double offsetAt(double x) {
    final xs = offsetXs, ys = offsetYs;
    if (xs.isEmpty) return 0;
    final last = xs.length - 1;
    if (last == 0) return ys[0];
    final k = last < _endFit ? last : _endFit;
    if (x < xs[0]) {
      return ys[0] + (ys[k] - ys[0]) / (xs[k] - xs[0]) * (x - xs[0]);
    }
    if (x > xs[last]) {
      return ys[last] +
          (ys[last] - ys[last - k]) / (xs[last] - xs[last - k]) * (x - xs[last]);
    }
    var lo = 0, hi = last;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (x - xs[lo]) / (xs[hi] - xs[lo]);
    return ys[lo] + (ys[hi] - ys[lo]) * t;
  }

  /// True when the point lies between [topY] and [bottomY] as the staff runs
  /// at column [x].
  bool containsY(double y, {required double x}) {
    final level = y - offsetAt(x);
    return level >= topY && level <= bottomY;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'topY': topY,
      'bottomY': bottomY,
      'lineYs': lineYs,
      if (offsetXs.isNotEmpty) 'offsetXs': offsetXs,
      if (offsetYs.isNotEmpty) 'offsetYs': offsetYs,
    };
  }

  factory DetectedStaff.fromJson(Map<String, dynamic> json) {
    List<double> doubles(String key) =>
        ((json[key] as List<dynamic>?) ?? const <dynamic>[])
            .map((value) => (value as num).toDouble())
            .toList(growable: false);
    return DetectedStaff(
      id: json['id'] as String,
      topY: (json['topY'] as num).toDouble(),
      bottomY: (json['bottomY'] as num).toDouble(),
      lineYs: doubles('lineYs'),
      offsetXs: doubles('offsetXs'),
      offsetYs: doubles('offsetYs'),
    );
  }

  @override
  String toString() => 'DetectedStaff(${toJson()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectedStaff &&
        other.id == id &&
        other.topY == topY &&
        other.bottomY == bottomY &&
        listEquals(other.lineYs, lineYs) &&
        listEquals(other.offsetXs, offsetXs) &&
        listEquals(other.offsetYs, offsetYs);
  }

  @override
  int get hashCode => Object.hash(
        id,
        topY,
        bottomY,
        Object.hashAll(lineYs),
        Object.hashAll(offsetXs),
        Object.hashAll(offsetYs),
      );
}
