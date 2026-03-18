import 'package:note_vision/core/models/score.dart';

import 'mapping_confidence_summary.dart';

class MappingResult {
  final Score score;
  final List<String> warnings;
  final List<String> errors;
  final MappingConfidenceSummary? confidenceSummary;

  const MappingResult({
    required this.score,
    this.warnings = const [],
    this.errors = const [],
    this.confidenceSummary,
  });

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasErrors => errors.isNotEmpty;
}