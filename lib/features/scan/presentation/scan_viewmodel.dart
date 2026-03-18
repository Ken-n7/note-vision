import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

enum ScanState { idle, preprocessing, detecting, done, error }

class ScanViewModel extends ChangeNotifier {
  final ImagePreprocessor _preprocessor;
  final SymbolDetector _detector;
  final ScoreMapperService? _mapper;

  ScanViewModel(this._preprocessor, this._detector, {ScoreMapperService? mapper})
      : _mapper = mapper;

  ScanState state = ScanState.idle;
  ScanResult? result;
  MappingResult? mappingResult;
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

      final detection = await _detector.detect(preprocessed);

      result = ScanResult(preprocessed: preprocessed, detection: detection);
      mappingResult = _mapper?.map(detection);
      state = ScanState.done;
    } catch (e) {
      errorMessage = e.toString();
      state = ScanState.error;
    }

    notifyListeners();
  }

  void reset() {
    result = null;
    mappingResult = null;
    state = ScanState.idle;
    errorMessage = null;
    notifyListeners();
  }
}