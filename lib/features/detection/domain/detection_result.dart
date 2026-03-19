import 'package:flutter/foundation.dart';

import 'detected_barline.dart';
import 'detected_staff.dart';
import 'detected_symbol.dart';

class DetectionResult {
  final String? imageId;
  final List<DetectedStaff> staffs;
  final List<DetectedBarline> barlines;
  final List<DetectedSymbol> symbols;

  const DetectionResult({
    this.imageId,
    this.staffs = const [],
    this.barlines = const [],
    this.symbols = const [],
  });

  bool get hasDetections =>
      staffs.isNotEmpty || barlines.isNotEmpty || symbols.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'imageId': imageId,
      'staffs': staffs.map((staff) => staff.toJson()).toList(growable: false),
      'barlines': barlines.map((barline) => barline.toJson()).toList(growable: false),
      'symbols': symbols.map((symbol) => symbol.toJson()).toList(growable: false),
    };
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      imageId: json['imageId'] as String?,
      staffs: ((json['staffs'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => DetectedStaff.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      barlines: ((json['barlines'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => DetectedBarline.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      symbols: ((json['symbols'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => DetectedSymbol.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  @override
  String toString() => 'DetectionResult(${toJson()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectionResult &&
        other.imageId == imageId &&
        listEquals(other.staffs, staffs) &&
        listEquals(other.barlines, barlines) &&
        listEquals(other.symbols, symbols);
  }

  @override
  int get hashCode => Object.hash(
        imageId,
        Object.hashAll(staffs),
        Object.hashAll(barlines),
        Object.hashAll(symbols),
      );
}
