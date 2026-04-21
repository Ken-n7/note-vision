import 'package:flutter/foundation.dart';

class DetectedStaff {
  final String id;
  final double topY;
  final double bottomY;
  final List<double> lineYs;

  const DetectedStaff({
    required this.id,
    required this.topY,
    required this.bottomY,
    required this.lineYs,
  });

  Map<String, Object?> toJson() {
    return {'id': id, 'topY': topY, 'bottomY': bottomY, 'lineYs': lineYs};
  }

  factory DetectedStaff.fromJson(Map<String, dynamic> json) {
    return DetectedStaff(
      id: json['id'] as String,
      topY: (json['topY'] as num).toDouble(),
      bottomY: (json['bottomY'] as num).toDouble(),
      lineYs: ((json['lineYs'] as List<dynamic>?) ?? const <dynamic>[])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
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
        listEquals(other.lineYs, lineYs);
  }

  @override
  int get hashCode => Object.hash(id, topY, bottomY, Object.hashAll(lineYs));
}
