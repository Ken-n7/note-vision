import 'package:note_vision/core/services/score_source_service.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
import 'package:note_vision/features/detection/domain/detection_result.dart';
import 'package:note_vision/features/detection/domain/symbol_detector.dart';
import 'package:note_vision/features/mapping/domain/mapping_result.dart';
import 'package:note_vision/features/mapping/domain/score_mapper_service.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

enum ScanState { idle, preprocessing, detectingStaves, detecting, done, error }

class ScanViewModel extends ChangeNotifier {
  final ImagePreprocessor _preprocessor;
  final StaffLineDetector _staffDetector;
  final SymbolDetector _detector;
  final ScoreMapperService? _mapper;

  ScanViewModel(
    this._preprocessor,
    this._staffDetector,
    this._detector, {
    ScoreMapperService? mapper,
  }) : _mapper = mapper;

  ScanState state = ScanState.idle;
  ScanResult? result;
  MappingResult? mappingResult;

  /// What went wrong, in words for the user.
  String? errorMessage;

  /// The underlying error, for debugging.
  String? errorDetail;

  bool _disposed = false;
  int _request = 0;
  Future<DetectionResult>? _pendingDetection;

  bool _isCurrent(int request) => !_disposed && request == _request;

  static const scanFailedMessage =
      'The photo could not be read. Try another photo of the page, flat and '
      'well lit.';

  @override
  void notifyListeners() {
    // The user can leave the scan screen while a scan is still running.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    // Loading/inference must finish before its native model can be released.
    if (_pendingDetection == null) _disposeDetector();
    super.dispose();
  }

  void _disposeDetector() {
    final detector = _detector;
    if (detector is TfliteSymbolDetector) detector.dispose();
  }

  Future<void> run(Uint8List bytes) async {
    if (_disposed) return;
    final request = ++_request;
    // Step 1 — preprocessing
    result = null;
    mappingResult = null;
    state = ScanState.preprocessing;
    errorMessage = null;
    errorDetail = null;
    notifyListeners();
    if (!_isCurrent(request)) return;

    try {
      final preprocessed = await _preprocessor.preprocess(bytes);
      if (!_isCurrent(request)) return;

      // Step 2 — staff line detection
      state = ScanState.detectingStaves;
      notifyListeners();
      if (!_isCurrent(request)) return;

      final List<DetectedStaff> staves = _staffDetector.detect(
        preprocessed.bytes,
      );

      // Step 3 — full-image symbol detection. Retries share one native model;
      // finish a superseded detection before using it for the latest photo.
      state = ScanState.detecting;
      notifyListeners();
      if (!_isCurrent(request)) return;
      while (_pendingDetection != null) {
        try {
          await _pendingDetection;
        } catch (_) {
          // An older photo's failure does not fail the replacement scan.
        }
        if (!_isCurrent(request)) return;
      }

      final pending = _detector.detect(preprocessed, staves);
      _pendingDetection = pending;
      final DetectionResult detection;
      try {
        detection = await pending;
      } finally {
        _pendingDetection = null;
        if (_disposed) _disposeDetector();
      }
      if (!_isCurrent(request)) return;

      final mapped = _mapper?.map(detection);
      MappingResult? mapping;
      if (mapped != null) {
        final score = await ScoreSourceService.attach(
          mapped.score,
          preprocessed.bytes,
          width: preprocessed.width,
          height: preprocessed.height,
        );
        if (!_isCurrent(request)) return;
        mapping = MappingResult(
          score: score,
          warnings: mapped.warnings,
          errors: mapped.errors,
          confidenceSummary: mapped.confidenceSummary,
          staffSource: mapped.staffSource,
        );
      }
      result = ScanResult(preprocessed: preprocessed, detection: detection);
      mappingResult = mapping;
      state = ScanState.done;
    } catch (e, stack) {
      if (!_isCurrent(request)) return;
      debugPrint('Scan failed: $e\n$stack');
      errorMessage = scanFailedMessage;
      errorDetail = e.toString();
      state = ScanState.error;
    }

    notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    _request++;
    result = null;
    mappingResult = null;
    state = ScanState.idle;
    errorMessage = null;
    errorDetail = null;
    notifyListeners();
  }
}
