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
  static const String _modelPath = 'assets/models/omr_model.tflite';
  static const double _confidenceThreshold = 0.75;
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
  Future<DetectionResult> detect(PreprocessedResult input) async {
    if (_interpreter == null) await init();

    final inputTensor = _imageToTensor(input.bytes);

    final output = List.generate(
      300,
      (_) => List.filled(6, 0.0),
    ).reshape([1, 300, 6]);

    _interpreter!.run(inputTensor, output);

    final symbols = _parseOutput(output[0] as List<List<double>>);
    final staffs = _deriveStaffsFromSymbols(symbols);

    return DetectionResult(staffs: staffs, symbols: symbols);
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
        DetectedSymbol.fromMusicSymbol(
          id: 'symbol-${detections.length}',
          symbol: MusicSymbol.values[classIndex],
          boundingBox: Rect.fromLTRB(x1, y1, x2, y2),
          confidence: confidence,
        ),
      );
    }

    return _nms(detections);
  }


  List<DetectedStaff> _deriveStaffsFromSymbols(List<DetectedSymbol> symbols) {
    final lineCenters = symbols
        .where((s) => s.musicSymbol == MusicSymbol.staffLine)
        .map((s) {
          final box = s.boundingBox;
          if (box == null) return null;
          return box.top + (box.height / 2);
        })
        .whereType<double>()
        .toList()
      ..sort();

    if (lineCenters.length < 5) return const [];

    final mergedCenters = <double>[];
    const mergeTol = 2.5;

    for (final y in lineCenters) {
      if (mergedCenters.isEmpty) {
        mergedCenters.add(y);
        continue;
      }
      final last = mergedCenters.last;
      if ((y - last).abs() <= mergeTol) {
        mergedCenters[mergedCenters.length - 1] = (last + y) / 2;
      } else {
        mergedCenters.add(y);
      }
    }

    if (mergedCenters.length < 5) return const [];

    final staffs = <DetectedStaff>[];
    var index = 0;

    while (index <= mergedCenters.length - 5) {
      final candidate = mergedCenters.sublist(index, index + 5);
      final gaps = <double>[];
      for (var i = 0; i < 4; i++) {
        gaps.add(candidate[i + 1] - candidate[i]);
      }

      final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
      if (avgGap <= 0) {
        index++;
        continue;
      }

      final spacingConsistent =
          gaps.every((g) => ((g - avgGap).abs() / avgGap) <= 0.35);

      if (!spacingConsistent) {
        index++;
        continue;
      }

      staffs.add(
        DetectedStaff(
          id: 'staff-${staffs.length}',
          topY: candidate.first,
          bottomY: candidate.last,
          lineYs: candidate,
        ),
      );

      index += 5;
    }

    return staffs;
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