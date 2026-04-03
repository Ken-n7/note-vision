import 'package:note_vision/features/preprocessing/domain/preprocessed_result.dart';

import '../../preprocessing/domain/staff_line_detector.dart';
import '../../detection/domain/detected_staff.dart';
import 'detection_result.dart';

export '../../preprocessing/domain/staff_line_detector.dart';

abstract class SymbolDetector {
  /// Run symbol detection on [input].
  ///
  /// [staves] are the stave boundaries produced by [StaffLineDetector].
  /// When [staves] is non-empty the detector tiles each stave crop through
  /// the model independently; when empty it falls back to full-image
  /// inference.
  Future<DetectionResult> detect(
    PreprocessedResult input,
    List<DetectedStaff> staves,
  );
}
