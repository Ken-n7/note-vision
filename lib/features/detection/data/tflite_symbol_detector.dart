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

    // The model was trained on full music sheet pages stretched to 640×640
    // (no letterboxing, no tiling). Always use the same preprocessing here.
    final tile = img.copyResize(
      fullImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final raw = _runInference(tile);
    final allDetections = _parseOutput(
      raw,
      scaleX: fullImage.width / _inputSize,
      scaleY: fullImage.height / _inputSize,
    );

    // Partition detections by role before NMS to avoid cross-class suppression.
    // combStaff → staff geometry; staffLine → structural (discarded);
    // everything else → musical symbols shown in the editor.
    final combStaffDetections = allDetections
        .where((s) => s.musicSymbol == MusicSymbol.combStaff)
        .toList();
    final musicalDetections = allDetections
        .where(
          (s) =>
              s.musicSymbol != MusicSymbol.combStaff &&
              s.musicSymbol != MusicSymbol.staffLine,
        )
        .toList();

    final mergedStaves = _mergeStaves(_nms(combStaffDetections), staves);
    final symbols = _nms(musicalDetections);

    debugPrint(
      '[TfliteSymbolDetector] ${fullImage.width}×${fullImage.height} → '
      '$_inputSize×$_inputSize | '
      '${combStaffDetections.length} combStaff → ${mergedStaves.length} stave(s) | '
      '${symbols.length} musical symbol(s)',
    );

    return DetectionResult(symbols: symbols, staffs: mergedStaves);
  }

  /// Builds the final staff list by preferring model-detected [combStaff]
  /// bboxes and supplementing with [projectorStaves] from
  /// [HorizontalProjectionStaffDetector] wherever the model missed a staff.
  List<DetectedStaff> _mergeStaves(
    List<DetectedSymbol> combStaffSymbols,
    List<DetectedStaff> projectorStaves,
  ) {
    // Convert each combStaff bbox into a DetectedStaff. Assume the bbox spans
    // exactly from the top staff line to the bottom staff line, giving 4 equal
    // gaps between 5 lines.
    final modelStaves = <DetectedStaff>[];
    for (int i = 0; i < combStaffSymbols.length; i++) {
      final box = combStaffSymbols[i].boundingBox;
      if (box == null) continue;
      final spacing = box.height / 4;
      modelStaves.add(
        DetectedStaff(
          id: 'model-staff-$i',
          topY: box.top,
          bottomY: box.bottom,
          lineYs: List.generate(5, (l) => box.top + l * spacing),
        ),
      );
    }

    // Add projector staves whose midpoint isn't already covered by a model staff.
    final supplementary = <DetectedStaff>[];
    for (final proj in projectorStaves) {
      final midY = (proj.topY + proj.bottomY) / 2;
      final covered = modelStaves.any(
        (ms) => midY >= ms.topY && midY <= ms.bottomY,
      );
      if (!covered) supplementary.add(proj);
    }

    if (modelStaves.isEmpty && supplementary.isEmpty) {
      debugPrint(
        '[TfliteSymbolDetector] No staves from model or projector — '
        'mapper will attempt SyntheticStaffBuilder.',
      );
    } else {
      debugPrint(
        '[TfliteSymbolDetector] Staves: ${modelStaves.length} model, '
        '${supplementary.length} projector supplement.',
      );
    }

    final merged = [...modelStaves, ...supplementary]
      ..sort((a, b) => a.topY.compareTo(b.topY));
    return merged;
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

  /// Converts raw model output rows into [DetectedSymbol]s in original-image
  /// pixel space. [scaleX]/[scaleY] map from 640×640 tile space back to the
  /// original image dimensions (origW/640 and origH/640 respectively).
  List<DetectedSymbol> _parseOutput(
    List<List<double>> rawOutput, {
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

      // Ultralytics YOLO TFLite NMS output: normalized 0–1 coords relative to
      // the 640×640 input. Multiply by _inputSize × scale to get original px.
      final x1 = detection[0] * _inputSize * scaleX;
      final y1 = detection[1] * _inputSize * scaleY;
      final x2 = detection[2] * _inputSize * scaleX;
      final y2 = detection[3] * _inputSize * scaleY;

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
