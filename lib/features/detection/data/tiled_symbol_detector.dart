import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:note_vision/features/detection/domain/detected_symbol.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';

/// Runs the symbol detector over overlapping tiles to provide a zoomed-in view
/// and then merges detections back into image-space coordinates.
class TiledSymbolDetector implements SymbolDetector {
  final SymbolDetector _baseDetector;
  final int gridColumns;
  final int gridRows;
  final double overlapFraction;
  final double iouThreshold;

  const TiledSymbolDetector(
    this._baseDetector, {
    this.gridColumns = 2,
    this.gridRows = 2,
    this.overlapFraction = 0.25,
    this.iouThreshold = 0.4,
  }) : assert(gridColumns >= 1),
       assert(gridRows >= 1),
       assert(overlapFraction >= 0 && overlapFraction < 1),
       assert(iouThreshold >= 0 && iouThreshold <= 1);

  @override
  Future<DetectionResult> detect(PreprocessedResult input) async {
    final decoded = img.decodeImage(input.bytes);
    if (decoded == null) {
      return _baseDetector.detect(input);
    }

    final tileWidth = math.max(1, (decoded.width / gridColumns).round());
    final tileHeight = math.max(1, (decoded.height / gridRows).round());

    final strideX = math.max(1, (tileWidth * (1 - overlapFraction)).round());
    final strideY = math.max(1, (tileHeight * (1 - overlapFraction)).round());

    final startXs = _buildStartPositions(decoded.width, tileWidth, strideX);
    final startYs = _buildStartPositions(decoded.height, tileHeight, strideY);

    final mergedSymbols = <DetectedSymbol>[];
    var tileIndex = 0;

    for (final y in startYs) {
      for (final x in startXs) {
        final cropW = math.min(tileWidth, decoded.width - x);
        final cropH = math.min(tileHeight, decoded.height - y);

        final tile = img.copyCrop(decoded, x: x, y: y, width: cropW, height: cropH);
        final resized = img.copyResize(
          tile,
          width: input.width,
          height: input.height,
          interpolation: img.Interpolation.linear,
        );

        final tileInput = PreprocessedResult(
          bytes: Uint8List.fromList(img.encodePng(resized)),
          width: input.width,
          height: input.height,
          scale: input.scale,
          padX: input.padX,
          padY: input.padY,
        );

        final tileResult = await _baseDetector.detect(tileInput);
        for (final symbol in tileResult.symbols) {
          final mapped = _mapBackToImage(
            symbol: symbol,
            tileLeft: x,
            tileTop: y,
            tileWidth: cropW,
            tileHeight: cropH,
            modelInputWidth: input.width,
            modelInputHeight: input.height,
            tileIndex: tileIndex,
          );
          mergedSymbols.add(mapped);
        }

        tileIndex += 1;
      }
    }

    return DetectionResult(
      imageId: input.hashCode.toString(),
      symbols: _nms(mergedSymbols),
    );
  }

  DetectedSymbol _mapBackToImage({
    required DetectedSymbol symbol,
    required int tileLeft,
    required int tileTop,
    required int tileWidth,
    required int tileHeight,
    required int modelInputWidth,
    required int modelInputHeight,
    required int tileIndex,
  }) {
    final sx = tileWidth / modelInputWidth;
    final sy = tileHeight / modelInputHeight;

    final mappedMeta = <String, Object?>{
      ...?symbol.metadata,
      'tileIndex': tileIndex,
    };

    return DetectedSymbol(
      id: '${symbol.id}-tile-$tileIndex',
      type: symbol.type,
      x: tileLeft + (symbol.x * sx),
      y: tileTop + (symbol.y * sy),
      width: symbol.width == null ? null : symbol.width! * sx,
      height: symbol.height == null ? null : symbol.height! * sy,
      confidence: symbol.confidence,
      metadata: mappedMeta,
    );
  }

  List<int> _buildStartPositions(int fullSize, int tileSize, int stride) {
    if (tileSize >= fullSize) return const [0];

    final starts = <int>[];
    var current = 0;

    while (current + tileSize < fullSize) {
      starts.add(current);
      current += stride;
    }

    final last = fullSize - tileSize;
    if (starts.isEmpty || starts.last != last) {
      starts.add(last);
    }

    return starts;
  }

  List<DetectedSymbol> _nms(List<DetectedSymbol> symbols) {
    if (symbols.isEmpty) return symbols;

    final sorted = [...symbols]
      ..sort((a, b) => (b.confidence ?? 0).compareTo(a.confidence ?? 0));

    final kept = <DetectedSymbol>[];

    for (final symbol in sorted) {
      final box = symbol.boundingBox;
      if (box == null) {
        kept.add(symbol);
        continue;
      }

      var suppressed = false;
      for (final existing in kept) {
        final existingBox = existing.boundingBox;
        if (existingBox == null) continue;
        if (_iou(box, existingBox) > iouThreshold) {
          suppressed = true;
          break;
        }
      }

      if (!suppressed) {
        kept.add(symbol);
      }
    }

    return kept;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0;

    return intersectionArea / unionArea;
  }
}
