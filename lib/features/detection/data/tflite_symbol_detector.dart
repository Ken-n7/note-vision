import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';

import '../../preprocessing/domain/preprocessed_result.dart';
import '../domain/detected_symbol.dart';
import '../domain/music_symbol.dart';
import '../domain/symbol_detector.dart';

class TfliteSymbolDetector implements SymbolDetector {
  static const String _modelPath = 'assets/models/omr_model.tflite';
  static const double _confidenceThreshold = 0.5;
  static const double _iouThreshold = 0.4;
  static const int _inputSize = 416;

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
  Future<List<DetectedSymbol>> detect(PreprocessedResult input) async {
    if (_interpreter == null) await init();

    final inputTensor = _imageToTensor(input.bytes);

    final output = List.generate(
      300,
      (_) => List.filled(6, 0.0),
    ).reshape([1, 300, 6]);

    _interpreter!.run(inputTensor, output);

    return _parseOutput(output[0] as List<List<double>>);
  }

  List<List<List<List<double>>>> _imageToTensor(Uint8List bytes) {
    final img.Image image = img.decodeImage(bytes)!;

    return List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );
  }

  List<DetectedSymbol> _parseOutput(List<List<double>> rawOutput) {
    final detections = <DetectedSymbol>[];

    for (final detection in rawOutput) {
      final confidence = detection[4];
      if (confidence < _confidenceThreshold) continue;

      final classIndex = detection[5].toInt();
      if (classIndex < 0 || classIndex >= MusicSymbol.values.length) continue;

      // Convert normalized coordinates (0–1) → pixels
      final x1 = detection[0] * _inputSize;
      final y1 = detection[1] * _inputSize;
      final x2 = detection[2] * _inputSize;
      final y2 = detection[3] * _inputSize;

      if (x2 <= x1 || y2 <= y1) continue;

      detections.add(
        DetectedSymbol(
          symbol: MusicSymbol.values[classIndex],
          boundingBox: Rect.fromLTRB(x1, y1, x2, y2),
          confidence: confidence,
        ),
      );
    }

    return _nms(detections);
  }

  List<DetectedSymbol> _nms(List<DetectedSymbol> detections) {
    if (detections.isEmpty) return detections;

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <DetectedSymbol>[];

    for (final detection in detections) {
      bool suppressed = false;
      for (final keptDetection in kept) {
        if (_iou(detection.boundingBox, keptDetection.boundingBox) >
            _iouThreshold) {
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
