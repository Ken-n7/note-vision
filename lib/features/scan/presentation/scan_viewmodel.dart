import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

enum ScanState {
  idle,
  preprocessing,
  staffLineDetection,
  staffLineRemoval,
  symbolDetectionClassification,
  symbolToStaffAssignment,
  pitchReconstruction,
  rhythmReconstruction,
  measureGrouping,
  scoreAssembly,
  done,
  error,
}

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

  bool get hasCompletedPipeline => state == ScanState.done;

  Future<void> run(Uint8List bytes) async {
    errorMessage = null;
    mappingResult = null;

    try {
      // Step 1 — preprocessing (grayscale, deskew, binarization, denoise)
      _setState(ScanState.preprocessing);
      final preprocessed = await _preprocessor.preprocess(bytes);

      // Step 2 + 3 — staff line detection/removal happen in detector stack.
      _setState(ScanState.staffLineDetection);
      _setState(ScanState.staffLineRemoval);

      // Step 4 — symbol detection/classification
      _setState(ScanState.symbolDetectionClassification);
      final detection = await _detector.detect(preprocessed);
      result = ScanResult(preprocessed: preprocessed, detection: detection);

      if (_mapper != null) {
        // Steps 5-9 are performed inside the mapper pipeline.
        _setState(ScanState.symbolToStaffAssignment);
        _setState(ScanState.pitchReconstruction);
        _setState(ScanState.rhythmReconstruction);
        _setState(ScanState.measureGrouping);
        _setState(ScanState.scoreAssembly);
        mappingResult = _mapper.map(detection);
      }

      _setState(ScanState.done);
    } catch (e) {
      errorMessage = e.toString();
      _setState(ScanState.error);
    }
  }

  void reset() {
    result = null;
    mappingResult = null;
    state = ScanState.idle;
    errorMessage = null;
    notifyListeners();
  }

  void _setState(ScanState next) {
    state = next;
    notifyListeners();
  }
}
