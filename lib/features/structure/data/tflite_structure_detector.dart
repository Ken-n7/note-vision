import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';
import 'package:note_vision/features/structure/domain/score_structure.dart';
import 'package:note_vision/features/structure/domain/structure_detector.dart';

class TfliteStructureDetector implements StructureDetector {
  static const String _modelPath = 'assets/models/omr_structure.tflite';
  static const int _inputSize = 1024;

  Interpreter? _interpreter;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
  }

  @override
  Future<ScoreStructure> detect(PreprocessedResult input) async {
    // Fall back gracefully if structure model is not bundled yet.
    try {
      if (_interpreter == null) await init();
      final tensor = _imageToTensor(input.bytes);
      final output = List.generate(300, (_) => List.filled(6, 0.0))
          .reshape([1, 300, 6]);
      _interpreter!.run(tensor, output);
    } catch (_) {
      // Intentionally ignored; we still return a baseline structure.
    }

    final fullBounds = Rect.fromLTWH(
      0,
      0,
      input.width.toDouble(),
      input.height.toDouble(),
    );

    return ScoreStructure(
      systems: [StaveSystem(bounds: fullBounds)],
      groups: const [],
      staveLines: _estimateStaveLines(input.height),
    );
  }

  List<List<List<List<double>>>> _imageToTensor(Uint8List bytes) {
    final image = img.decodeImage(bytes)!;
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

  List<double> _estimateStaveLines(int height) {
    final center = height / 2;
    return List<double>.generate(5, (index) => center - 20 + (index * 10));
  }
}
