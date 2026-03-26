import 'package:flutter/material.dart';
import 'package:note_vision/features/cropping/domain/stave_crop.dart';

import 'music_symbol.dart';

class DetectedSymbol {
  final String id;
  final String type;
  final double x;
  final double y;
  final double? width;
  final double? height;
  final double? confidence;
  final Map<String, Object?>? metadata;

  const DetectedSymbol({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.confidence,
    this.metadata,
  });

  factory DetectedSymbol.fromMusicSymbol({
    required String id,
    required MusicSymbol symbol,
    required Rect boundingBox,
    double? confidence,
    Map<String, Object?>? metadata,
  }) {
    return DetectedSymbol(
      id: id,
      type: symbol.name,
      x: boundingBox.left,
      y: boundingBox.top,
      width: boundingBox.width,
      height: boundingBox.height,
      confidence: confidence,
      metadata: metadata,
    );
  }

  Rect? get boundingBox {
    if (width == null || height == null) return null;
    return Rect.fromLTWH(x, y, width!, height!);
  }

  MusicSymbol? get musicSymbol {
    try {
      return MusicSymbol.fromString(type);
    } on ArgumentError {
      return null;
    }
  }

  Rect? toOriginalCoordinates({
    required double scale,
    required int padX,
    required int padY,
  }) {
    final box = boundingBox;
    if (box == null) return null;

    return Rect.fromLTWH(
      (box.left - padX) / scale,
      (box.top - padY) / scale,
      box.width / scale,
      box.height / scale,
    );
  }

  DetectedSymbol toStaveCoordinates(StaveCrop crop) {
    return DetectedSymbol(
      id: id,
      type: type,
      x: x + crop.offsetX,
      y: y + crop.offsetY,
      width: width,
      height: height,
      confidence: confidence,
      metadata: {
        ...?metadata,
        'staveIndex': crop.staveIndex,
        'instrumentGroup': crop.instrumentGroup,
        'isBracePair': crop.isBracePair,
      },
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'confidence': confidence,
      'metadata': metadata,
    };
  }

  factory DetectedSymbol.fromJson(Map<String, dynamic> json) {
    return DetectedSymbol(
      id: json['id'] as String,
      type: json['type'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
    );
  }

  @override
  String toString() => 'DetectedSymbol(${toJson()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DetectedSymbol &&
        other.id == id &&
        other.type == type &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height &&
        other.confidence == confidence &&
        _deepEquals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        x,
        y,
        width,
        height,
        confidence,
        _deepHash(metadata),
      );

  static bool _deepEquals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) return false;
        if (!_deepEquals(entry.value, right[entry.key])) return false;
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static int? _deepHash(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      final keys = value.keys.toList()..sort((a, b) => '$a'.compareTo('$b'));
      return Object.hashAll(
        keys.map((key) => Object.hash(key, _deepHash(value[key]))),
      );
    }
    if (value is List) {
      return Object.hashAll(value.map(_deepHash));
    }
    return value.hashCode;
  }
}
