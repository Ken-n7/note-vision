import 'package:note_vision/core/services/score_source_service.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:note_vision/features/detection/data/tflite_symbol_detector.dart';
import 'package:note_vision/features/preprocessing/domain/image_preprocessor.dart';
import 'package:note_vision/features/detection/domain/detected_staff.dart';
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
    // The detector holds the model in native memory; free it with the screen.
    final detector = _detector;
    if (detector is TfliteSymbolDetector) detector.dispose();
    super.dispose();
  }

  Future<void> run(Uint8List bytes) async {
    // Step 1 — preprocessing
    state = ScanState.preprocessing;
    errorMessage = null;
    errorDetail = null;
    notifyListeners();

    try {
      final preprocessed = await _preprocessor.preprocess(bytes);

      // Step 2 — staff line detection
      state = ScanState.detectingStaves;
      notifyListeners();

      final List<DetectedStaff> staves = _staffDetector.detect(
        preprocessed.bytes,
      );

      // Step 3 — symbol detection (stave-tiled or full-image fallback)
      state = ScanState.detecting;
      notifyListeners();

      final detection = await _detector.detect(preprocessed, staves);

      result = ScanResult(preprocessed: preprocessed, detection: detection);
      final mapped = _mapper?.map(detection);
      if (mapped != null) {
        final score = await ScoreSourceService.attach(
          mapped.score,
          preprocessed.bytes,
          width: preprocessed.width,
          height: preprocessed.height,
        );
        mappingResult = MappingResult(
          score: score,
          warnings: mapped.warnings,
          errors: mapped.errors,
          confidenceSummary: mapped.confidenceSummary,
          staffSource: mapped.staffSource,
        );
      }
      state = ScanState.done;
    } catch (e, stack) {
      debugPrint('Scan failed: $e\n$stack');
      errorMessage = scanFailedMessage;
      errorDetail = e.toString();
      state = ScanState.error;
    }

    notifyListeners();
  }

  void reset() {
    result = null;
    mappingResult = null;
    state = ScanState.idle;
    errorMessage = null;
    errorDetail = null;
    notifyListeners();
  }
}
