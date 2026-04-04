import 'package:note_vision/core/models/score.dart';

import 'mapping_confidence_summary.dart';

class MappingResult {
  final Score score;
  final List<String> warnings;
  final List<String> errors;
  final MappingConfidenceSummary? confidenceSummary;

  /// `'detected'` when real stave geometry was used, `'synthetic'` when pitch
  /// positions were estimated from symbol bounding boxes because stave
  /// detection found nothing.  `null` means the information was not recorded
  /// (legacy callers).
  final String? staffSource;

  const MappingResult({
    required this.score,
    this.warnings = const [],
    this.errors = const [],
    this.confidenceSummary,
    this.staffSource,
  });

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasErrors => errors.isNotEmpty;
}