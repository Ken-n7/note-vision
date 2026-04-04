import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../preprocessing/domain/preprocessed_result.dart';
import '../domain/detected_staff.dart';
import '../domain/detected_symbol.dart';
import '../domain/detection_result.dart';
import '../domain/music_symbol.dart';
import '../domain/symbol_detector.dart';

class TfliteSymbolDetector implements SymbolDetector {
  static const String _modelPath = 'assets/models/best_int8.tflite';
  static const double _confidenceThreshold = 0.75;
  static const double _iouThreshold = 0.4;
  static const int _inputSize = 640;

  Interpreter? _interpreter;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);
    debugPrint('Input shape: ${inputTensor.shape}');
    debugPrint('Input type: ${inputTensor.type}');
    debugPrint('Output shape: ${outputTensor.shape}');
    debugPrint('Output type: ${outputTensor.type}');
  }

  void dispose() {
    _interpreter?.close();
  }

  @override
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  ) async {
    if (_interpreter == null) await init();

    final img.Image fullImage = img.decodeImage(input.bytes)!;

    final List<DetectedSymbol> allSymbols;

    if (staves.isNotEmpty) {
      debugPrint(
        '[TfliteSymbolDetector] ${staves.length} stave(s) detected:\n'
        '${staves.map((s) => '  ${s.id}: lineYs=${s.lineYs.map((y) => y.toStringAsFixed(1)).toList()}').join('\n')}',
      );
      // Stave-based tiling: one inference per stave.
      final symbols = <DetectedSymbol>[];
      for (final staff in staves) {
        final tileSymbols = await _detectStave(fullImage, staff);
        symbols.addAll(tileSymbols);
      }
      allSymbols = _nms(symbols);
    } else {
      // Fallback: letterbox the full image into 640×640 (preserving aspect
      // ratio) and run a single inference.  Letterboxing prevents the model
      // from seeing a distorted view, which was the cause of detection
      // misalignment when the image is tall (e.g. 736×1041).
      debugPrint(
        '[TfliteSymbolDetector] No staff lines detected — falling back to '
        'full-image letterbox inference. lineYs will be empty; pitch '
        'reconstruction will produce warnings.',
      );
      final scale = _inputSize / fullImage.width < _inputSize / fullImage.height
          ? _inputSize / fullImage.width
          : _inputSize / fullImage.height;
      final scaledW = (fullImage.width * scale).round();
      final scaledH = (fullImage.height * scale).round();
      final padX = (_inputSize - scaledW) ~/ 2;
      final padY = (_inputSize - scaledH) ~/ 2;

      final scaled = img.copyResize(
        fullImage,
        width: scaledW,
        height: scaledH,
        interpolation: img.Interpolation.linear,
      );
      final tile = img.Image(
        width: _inputSize,
        height: _inputSize,
        numChannels: 3,
      );
      img.fill(tile, color: img.ColorRgb8(114, 114, 114)); // YOLO grey padding
      img.compositeImage(tile, scaled, dstX: padX, dstY: padY);

      debugPrint(
        '[TfliteSymbolDetector] Letterbox: scale=$scale '
        'scaledW=$scaledW scaledH=$scaledH padX=$padX padY=$padY',
      );

      // Remap: tile_pixel = detection * _inputSize
      // orig = (tile_pixel - pad) / scale
      // Combined: orig = detection * _inputSize / scale - pad / scale
      final invScale = 1.0 / scale;
      final raw = _runInference(tile);
      allSymbols = _nms(
        _parseOutput(
          raw,
          offsetX: -padX * invScale,
          offsetY: -padY * invScale,
          scaleX: _inputSize * invScale,
          scaleY: _inputSize * invScale,
        ),
      );
    }

    return DetectionResult(symbols: allSymbols, staffs: staves);
  }

  /// Runs inference on a single stave crop and maps detections back to
  /// original-image coordinates.
  Future<List<DetectedSymbol>> _detectStave(
    img.Image fullImage,
    DetectedStaff staff,
  ) async {
    final cropY = staff.topY.round().clamp(0, fullImage.height - 1);
    final cropH =
        (staff.bottomY.round() - cropY).clamp(1, fullImage.height - cropY);

    final crop = img.copyCrop(
      fullImage,
      x: 0,
      y: cropY,
      width: fullImage.width,
      height: cropH,
    );

    final tile = img.copyResize(
      crop,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final scaleX = fullImage.width / _inputSize;
    final scaleY = cropH / _inputSize;

    final raw = _runInference(tile);
    return _parseOutput(
      raw,
      offsetX: 0,
      offsetY: cropY.toDouble(),
      scaleX: scaleX,
      scaleY: scaleY,
    );
  }

  List<List<double>> _runInference(img.Image tile) {
    final inputData = _imageToTensor(tile);

    // Wrap in nested list so tflite_flutter maps it to [1, 640, 640, 3].
    final input = [
      List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final base = (y * _inputSize + x) * 3;
            return [inputData[base], inputData[base + 1], inputData[base + 2]];
          },
        ),
      ),
    ];

    final output = List.generate(
      300,
      (_) => List.filled(6, 0.0),
    ).reshape([1, 300, 6]);

    _interpreter!.run(input, output);

    return output[0] as List<List<double>>;
  }

  /// Builds the input tensor from a 640×640 RGB image.
  ///
  /// The Ultralytics INT8 TFLite export keeps float32 I/O (internal ops are
  /// quantized but the tensor interface remains float32). Pixels are normalized
  /// to [0.0, 1.0].
  Float32List _imageToTensor(img.Image tile) {
    final data = Float32List(_inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = tile.getPixel(x, y);
        data[idx++] = pixel.r.toInt() / 255.0;
        data[idx++] = pixel.g.toInt() / 255.0;
        data[idx++] = pixel.b.toInt() / 255.0;
      }
    }
    return data;
  }

  /// Converts raw model output rows into [DetectedSymbol]s remapped to
  /// original-image pixel space via [offsetX]/[offsetY] (the crop origin)
  /// and [scaleX]/[scaleY] (crop-to-original scale factors).
  List<DetectedSymbol> _parseOutput(
    List<List<double>> rawOutput, {
    required double offsetX,
    required double offsetY,
    required double scaleX,
    required double scaleY,
  }) {
    final detections = <DetectedSymbol>[];
    int counter = 0;

    for (final detection in rawOutput) {
      final confidence = detection[4];
      if (confidence < _confidenceThreshold) continue;

      final classIndex = detection[5].toInt();
      if (classIndex < 0 || classIndex >= MusicSymbol.values.length) continue;

      // Ultralytics YOLO TFLite NMS output uses normalized 0–1 coordinates
      // relative to the 640×640 input tile. Multiply by _inputSize first to
      // get tile-pixel coords, then scale to original-image pixel space.
      final x1 = detection[0] * _inputSize * scaleX + offsetX;
      final y1 = detection[1] * _inputSize * scaleY + offsetY;
      final x2 = detection[2] * _inputSize * scaleX + offsetX;
      final y2 = detection[3] * _inputSize * scaleY + offsetY;

      if (x2 <= x1 || y2 <= y1) continue;

      detections.add(
        DetectedSymbol.fromMusicSymbol(
          id: 'symbol-$counter',
          symbol: MusicSymbol.values[classIndex],
          boundingBox: Rect.fromLTRB(x1, y1, x2, y2),
          confidence: confidence,
        ),
      );
      counter++;
    }

    return detections;
  }

  List<DetectedSymbol> _nms(List<DetectedSymbol> detections) {
    if (detections.isEmpty) return detections;

    detections.sort((a, b) => (b.confidence ?? 0).compareTo(a.confidence ?? 0));

    final kept = <DetectedSymbol>[];

    for (final detection in detections) {
      final detectionBox = detection.boundingBox;
      if (detectionBox == null) {
        kept.add(detection);
        continue;
      }

      bool suppressed = false;
      for (final keptDetection in kept) {
        final keptBox = keptDetection.boundingBox;
        if (keptBox == null) continue;

        if (_iou(detectionBox, keptBox) > _iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(detection);
    }

    return kept;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    return intersectionArea / unionArea;
  }
}
