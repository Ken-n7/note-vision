import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

enum ScanState { idle, preprocessing, done, error }

class ScanViewModel extends ChangeNotifier {
  final ImagePreprocessor _preprocessor;

  ScanViewModel(this._preprocessor);

  ScanState state = ScanState.idle;
  ScanResult? result;
  String? errorMessage;

  Future<void> run(Uint8List bytes) async {
    state = ScanState.preprocessing;
    errorMessage = null;
    notifyListeners();

    try {
      final preprocessed = await _preprocessor.preprocess(bytes);

      // detection will be added here later:
      // final symbols = await _detector.detect(preprocessed);

      result = ScanResult(preprocessed: preprocessed);
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