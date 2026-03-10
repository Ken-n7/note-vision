import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

enum ScanState { idle, preprocessing, detecting, done, error }

class ScanViewModel extends ChangeNotifier {
  final ImagePreprocessor _preprocessor;
  final SymbolDetector _detector;

  ScanViewModel(this._preprocessor, this._detector);

  ScanState state = ScanState.idle;
  ScanResult? result;
  String? errorMessage;

  Future<void> run(Uint8List bytes) async {
    // Step 1 — preprocessing
    state = ScanState.preprocessing;
    errorMessage = null;
    notifyListeners();

    try {
      final preprocessed = await _preprocessor.preprocess(bytes);

      // Step 2 — detection
      state = ScanState.detecting;
      notifyListeners();

      final symbols = await _detector.detect(preprocessed);

      result = ScanResult(preprocessed: preprocessed, symbols: symbols);
      state = ScanState.done;
    } catch (e) {
      errorMessage = e.toString();
      state = ScanState.error;
    }

    notifyListeners();
  }

  void reset() {
    result = null;
    state = ScanState.idle;
    errorMessage = null;
    notifyListeners();
  }
}